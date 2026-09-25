import AppKit
import QuickLookThumbnailing
import SwiftUI

/// The item ⌘⌫ acts on. An ejectable item is ejected; anything else only leaves
/// the shelf, because the shelf holds references and never deletes files.
enum ShelfSelection: Hashable {
    case file(UUID)
    case volume(String)

    /// Returns what stays selected: an ejecting disk keeps its highlight until
    /// it disappears, and a removed file clears it.
    @MainActor
    func performDelete(shelf: FileShelf, volumes: ShelfVolumes) -> ShelfSelection? {
        switch self {
        case .volume(let id):
            guard let volume = volumes.volumes.first(where: { $0.id == id }) else { return nil }
            volumes.eject(volume)
            return self
        case .file(let id):
            guard let file = shelf.files.first(where: { $0.id == id }) else { return nil }
            // Ejecting an image detaches all of its volumes, so the first one covers them.
            if let volume = volumes.mountedImages(for: file.url).first {
                volumes.eject(volume)
                return self
            }
            shelf.remove(id)
            return nil
        }
    }
}

struct FileShelfView: View {
    @ObservedObject var shelf: FileShelf
    @ObservedObject var volumes: ShelfVolumes
    @ObservedObject var drag: ShelfDragState
    let addFiles: () -> Void
    let close: () -> Void
    @State private var ejectTargeted = false
    @State private var openTargeted = false
    @State private var selection: ShelfSelection?

    static let inset: CGFloat = 12
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 4)

    private var drop: ShelfDrop { ShelfDrop(urls: drag.urls, volumes: volumes.volumes) }
    private var ejectTarget: ShelfVolume? {
        guard drag.urls.count == 1 else { return nil }
        return drop.volumes.first ?? volumes.mountedImages(for: drag.urls[0]).first
    }
    private var imageToOpen: URL? {
        guard drag.urls.count == 1, let url = drop.files.first,
              url.pathExtension.lowercased() == "dmg", ejectTarget == nil else { return nil }
        return url
    }
    /// Once files are shelved the whole panel accepts drops, so the card only
    /// earns its space while a drag is in progress or the shelf is empty.
    private var showsDropTargets: Bool { shelf.files.isEmpty || !drag.urls.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            // The first layout is the panel's natural height; the scrolling one
            // only takes over when the screen is too short for it.
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }
            }
        }
        .frame(width: FileShelfController.width)
        .background(Theme.canvas)
        .foregroundStyle(Theme.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.groupBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onExitCommand(perform: close)
        .background {
            Button("Add files", action: addFiles).keyboardShortcut("o").hidden()
            Button("Eject or remove selection") {
                selection = selection?.performDelete(shelf: shelf, volumes: volumes)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(selection == nil)
            .hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text("Shelf")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            if !shelf.files.isEmpty {
                Text("\(shelf.files.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.controlBackground, in: Capsule())
                    .padding(.leading, 6)
                    .accessibilityLabel("\(shelf.files.count) items")
            }
            Spacer(minLength: 8)
            if !shelf.files.isEmpty {
                Button("Clear") { shelf.clear() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(minWidth: 40, minHeight: 24)
                    .help("Remove everything from the shelf. Original files stay in place.")
            }
            ShelfIconButton(symbol: "plus", label: "Add files to shelf", action: addFiles)
            ShelfIconButton(symbol: "xmark", label: "Close shelf", action: close)
        }
        .padding(.leading, Self.inset + 2)
        .padding(.trailing, Self.inset - 4)
        .padding(.vertical, 8)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDropTargets { dropTargets }
            if !shelf.files.isEmpty { filesGrid }
            disksSection
            if let notice = ShelfNotice.latest(shelf.notice, volumes.notice) { noticeRow(notice) }
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 2)
        .padding(.bottom, Self.inset)
    }

    private var dropTargets: some View {
        HStack(spacing: 8) {
            if drop.volumes.isEmpty {
                ShelfDropTarget(accepts: { !ShelfDrop(urls: $0, volumes: volumes.volumes).files.isEmpty },
                                onHover: { drag.enter($0) }, onDrop: { urls in
                    let result = shelf.add(ShelfDrop(urls: urls, volumes: volumes.volumes).files)
                    drag.finish()
                    return result
                }, onExit: { drag.isTargeted = false }) {
                    ShelfDropCard(symbol: "tray.and.arrow.down", title: "Drop to keep",
                                  detail: drag.urls.isEmpty ? "Originals stay where they are" : "Drag out when you need it",
                                  highlighted: drag.isTargeted && !ejectTargeted && !openTargeted)
                }
            }
            if let volume = ejectTarget {
                ShelfDropTarget(accepts: { urls in
                    guard urls.count == 1 else { return false }
                    let actual = ShelfDrop(urls: urls, volumes: volumes.volumes)
                    return actual.volumes.contains(volume) || volumes.mountedImages(for: urls[0]).contains(volume)
                }, onHover: { drag.enter($0); ejectTargeted = true }, onDrop: { _ in
                    volumes.eject(volume)
                    drag.finish()
                    return true
                }, onExit: { ejectTargeted = false }) {
                    ShelfDropCard(symbol: "eject", title: "Drop to eject", detail: volume.name,
                                  highlighted: ejectTargeted)
                }
            } else if let image = imageToOpen {
                ShelfDropTarget(accepts: { $0 == [image] }, onHover: { drag.enter($0); openTargeted = true },
                                onDrop: { _ in shelf.open(image); drag.finish(); return true },
                                onExit: { openTargeted = false }) {
                    ShelfDropCard(symbol: "opticaldisc", title: "Drop to open", detail: "Mount the disk image",
                                  highlighted: openTargeted)
                }
            }
        }
        .frame(height: 76)
        .accessibilityElement(children: .contain)
    }

    private var filesGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(shelf.files) { file in
                ShelfFileTile(file: file, shelf: shelf, volumes: volumes, drag: drag, selection: $selection)
            }
        }
        .padding(6)
        .groupSurface()
    }

    private var disksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Disks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if volumes.isRefreshing {
                    ProgressView().controlSize(.mini).frame(width: 24, height: 24)
                        .accessibilityLabel("Refreshing disks")
                } else {
                    ShelfIconButton(symbol: "arrow.clockwise", label: "Refresh disks") {
                        volumes.notice = nil
                        volumes.refresh()
                        shelf.refresh()
                    }
                }
            }
            .padding(.leading, 2)
            if volumes.volumes.isEmpty {
                Text(volumes.isRefreshing ? "Looking for disks…" : "No external disks or open disk images")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(volumes.volumes) { volume in
                        ShelfVolumeRow(volume: volume, volumes: volumes, selection: $selection)
                        if volume.id != volumes.volumes.last?.id {
                            Theme.separator.frame(height: 1).padding(.leading, 40)
                        }
                    }
                }
                .groupSurface()
            }
        }
    }

    private func noticeRow(_ notice: ShelfNotice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.isError ? Theme.primary : Theme.accent)
                .accessibilityHidden(true)
            Text(notice.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                volumes.notice = nil
                shelf.notice = nil
            } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 24, height: 24) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .accessibilityLabel("Dismiss message")
        }
        .font(.system(size: 11))
        .padding(.leading, 2)
    }
}

private struct ShelfDropCard: View {
    let symbol: String
    let title: String
    let detail: String
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.accent.opacity(highlighted ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(highlighted ? Theme.accent : Theme.accent.opacity(0.35),
                              style: StrokeStyle(lineWidth: highlighted ? 1.5 : 1, dash: highlighted ? [] : [4, 3]))
        }
        .scaleEffect(highlighted ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: highlighted)
        .accessibilityElement(children: .combine)
    }
}

private struct ShelfFileTile: View {
    let file: ShelfFile
    @ObservedObject var shelf: FileShelf
    @ObservedObject var volumes: ShelfVolumes
    @ObservedObject var drag: ShelfDragState
    @Binding var selection: ShelfSelection?
    @State private var hovering = false
    @FocusState private var menuFocused: Bool

    private var isSelected: Bool { selection == .file(file.id) }

    var body: some View {
        VStack(spacing: 4) {
            ShelfDragSource(resolveURL: { shelf.availableURL(for: file.id) }, onDragging: { drag.isDraggingOut = $0 },
                            onClick: { selection = .file(file.id) }) {
                ShelfFilePreview(url: file.url)
                    .frame(width: 40, height: 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(file.isAvailable ? 1 : 0.35)
                    .contentShape(Rectangle())
            }
            .frame(height: 46)
            Text(file.name)
                .font(.system(size: 10))
                .foregroundStyle(file.isAvailable ? Theme.primary : Theme.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .top)
        }
        .padding(.top, 4)
        .padding(.horizontal, 2)
        .background(isSelected ? Theme.accent.opacity(0.14) : Theme.controlBackground.opacity(hovering ? 0.8 : 0),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.accent.opacity(isSelected ? 0.6 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            actions
                .opacity(hovering || menuFocused ? 1 : 0)
                .offset(x: 4, y: -4)
        }
        .onHover { hovering = $0 }
        .contextMenu { menuItems }
        .help(file.isAvailable ? "Drag \(file.name) into another app" : "\(file.name) is unavailable")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(file.isAvailable ? file.name : "\(file.name), unavailable")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var actions: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 20, height: 20)
                .background(Theme.groupBackground, in: Circle())
                .overlay(Circle().strokeBorder(Theme.groupBorder, lineWidth: 1))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .focused($menuFocused)
        .accessibilityLabel("Actions for \(file.name)")
    }

    @ViewBuilder private var menuItems: some View {
        Button("Open") { shelf.open(file.id) }.disabled(!file.isAvailable)
        Button("Copy File") { shelf.copy(file.id) }.disabled(!file.isAvailable)
        Button("Show in Finder") { shelf.reveal(file.id) }.disabled(!file.isAvailable)
        ForEach(volumes.mountedImages(for: file.url)) { volume in
            Button("Eject \(volume.name)") { volumes.eject(volume) }
                .disabled(volumes.ejecting.contains(volume.id))
        }
        Divider()
        Button("Remove from Shelf") { shelf.remove(file.id) }
    }
}

private struct ShelfFilePreview: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(thumbnail == nil ? 0 : 0.18), radius: 1.5, y: 1)
            .accessibilityHidden(true)
            .task(id: url) {
                thumbnail = nil
                let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 80, height: 80),
                                                           scale: 2, representationTypes: .all)
                do {
                    let result = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                    try Task.checkCancellation()
                    thumbnail = result.nsImage
                } catch {
                    // Unsupported formats and offline files still have a native file icon.
                    QLThumbnailGenerator.shared.cancel(request)
                }
            }
    }
}

private struct ShelfVolumeRow: View {
    let volume: ShelfVolume
    @ObservedObject var volumes: ShelfVolumes
    @Binding var selection: ShelfSelection?

    private var isSelected: Bool { selection == .volume(volume.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volume.symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(volumes.ejecting.contains(volume.id) ? "Ejecting…" : volume.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            if volumes.ejecting.contains(volume.id) {
                ProgressView().controlSize(.mini).frame(width: 24, height: 24)
                    .accessibilityLabel("Ejecting \(volume.name)")
            } else {
                ShelfIconButton(symbol: "eject", label: "Eject \(volume.name)") { volumes.eject(volume) }
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(Theme.accent.opacity(isSelected ? 0.14 : 0))
        .contentShape(Rectangle())
        .onTapGesture { selection = .volume(volume.id) }
        .help("Select and press Command-Delete to eject")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ShelfIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}
