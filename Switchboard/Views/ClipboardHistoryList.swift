import AppKit
import SwiftUI

/// Recent clips, and where captured or translated text becomes readable
/// instead of only existing on the clipboard.
struct ClipboardHistoryList: View {
    @ObservedObject var store: TweakStore

    var body: some View {
        VStack(spacing: 0) {
            if store.clips.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.emptyStateGlyph)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    Text("Nothing copied yet")
                        .font(.rowTitle)
                        .foregroundStyle(Theme.primary)
                    Text("Anything you copy while Switchboard runs shows up here")
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .padding(.horizontal, 20)
            } else {
                ForEach(Array(store.clips.enumerated()), id: \.element.id) { index, clip in
                    ClipRow(clip: clip, store: store)
                    if index < store.clips.count - 1 {
                        Theme.separator.frame(height: 1).padding(.leading, Theme.rowInset)
                    }
                }
            }
        }
        .groupSurface()
    }
}

private struct ClipRow: View {
    let clip: ClipEntry
    @ObservedObject var store: TweakStore
    @State private var expanded = false

    /// A long single-line clip is expandable too, and "Show all 1 lines" is
    /// not a sentence.
    private var expandLabel: String {
        clip.lineCount > 1 ? "Show all \(clip.lineCount) lines" : "Show more"
    }

    private var timestamp: String {
        let elapsed = Date().timeIntervalSince(clip.date)
        // RelativeDateTimeFormatter renders anything recent as "in 0 secs".
        guard elapsed >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: clip.date, relativeTo: Date())
    }

    private var accessibilitySummary: String {
        if clip.isImage { return "image, \(clip.sizeLabel)" }
        let preview = String(clip.preview.prefix(40))
        return preview.isEmpty ? "text clip" : "text clip: \(preview)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if clip.isImage {
                HStack(spacing: 8) {
                    if let data = clip.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 180, maxHeight: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Theme.groupBorder, lineWidth: 1)
                            )
                            .accessibilityLabel("Copied image")
                            .accessibilityValue(clip.sizeLabel)
                    } else {
                        Label("Image preview unavailable", systemImage: "photo")
                            .font(.rowSubtitle)
                            .foregroundStyle(Theme.secondary)
                    }
                    Text(clip.sizeLabel)
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                // Selectable so a translation can be read and picked apart here,
                // rather than pasted somewhere else just to see it.
                Text(expanded ? clip.text : clip.preview)
                    .font(.bodyText)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !clip.isImage, clip.lineCount > 2 || clip.preview.count > 90 {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Show less" : expandLabel)
                        .frame(minHeight: 28)
                }
                .buttonStyle(.borderless)
                .font(.rowSubtitle)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(accessibilitySummary)")
            }
            HStack(spacing: 8) {
                if let note = clip.note {
                    Text(note)
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.controlBackground,
                                    in: RoundedRectangle(cornerRadius: 4))
                }
                Text(timestamp)
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                Button { store.copyBack(clip) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(minHeight: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .font(.rowSubtitle)
                .accessibilityLabel("Copy \(accessibilitySummary)")
                .help("Copy this item to the clipboard")
                Button {
                    store.removeClip(clip)
                } label: {
                    Image(systemName: "trash")
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(accessibilitySummary)")
                .help("Remove this item from history")
            }
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .rowHoverHighlight()
        .accessibilityElement(children: .contain)
    }
}
