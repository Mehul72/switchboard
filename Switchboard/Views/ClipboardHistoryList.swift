import AppKit
import SwiftUI

/// Recent clips, and where captured or translated text becomes readable
/// instead of only existing on the clipboard.
struct ClipboardHistoryList: View {
    @ObservedObject var store: TweakStore

    var body: some View {
        VStack(spacing: 0) {
            if store.clips.isEmpty {
                VStack(spacing: 5) {
                    Text("Nothing copied yet")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                    Text("Anything you copy while Switchboard runs shows up here")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
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
        .background(Theme.groupBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Theme.groupBorder, lineWidth: 1)
        )
    }
}

private struct ClipRow: View {
    let clip: ClipEntry
    @ObservedObject var store: TweakStore
    @State private var hovering = false
    @State private var expanded = false

    private var timestamp: String {
        let elapsed = Date().timeIntervalSince(clip.date)
        // RelativeDateTimeFormatter renders anything recent as "in 0 secs".
        guard elapsed >= 60 else { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: clip.date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let note = clip.note {
                    Text(note)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 4))
                }
                Text(timestamp)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.tertiary)
                Spacer(minLength: 0)
                if hovering {
                    Button("Copy") { store.copyBack(clip) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                    Button {
                        store.removeClip(clip)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove clip")
                }
            }

            if clip.isImage {
                HStack(spacing: 8) {
                    if let data = clip.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 150, maxHeight: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Theme.groupBorder, lineWidth: 1)
                            )
                    }
                    Text(clip.sizeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                // Selectable so a translation can be read and picked apart here,
                // rather than pasted somewhere else just to see it.
                Text(expanded ? clip.text : clip.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !clip.isImage, clip.lineCount > 2 || clip.preview.count > 90 {
                Button(expanded ? "Show less" : "Show all \(clip.lineCount) lines") {
                    expanded.toggle()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
            }
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
