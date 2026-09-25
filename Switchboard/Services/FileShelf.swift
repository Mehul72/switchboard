import AppKit
import Combine
import OSLog

struct ShelfNotice: Equatable {
    let text: String
    var isError = false
    let date = Date()

    static func latest(_ notices: ShelfNotice?...) -> ShelfNotice? {
        notices.compactMap { $0 }.max { $0.date < $1.date }
    }
}

struct ShelfFile: Identifiable {
    let id = UUID()
    var url: URL
    let bookmark: Data
    var isAvailable = true

    var name: String { url.lastPathComponent }
    var location: String { url.deletingLastPathComponent().lastPathComponent }
}

@MainActor
final class FileShelf: ObservableObject {
    static let limit = 40
    @Published private(set) var files: [ShelfFile] = []
    @Published var notice: ShelfNotice?
    var onCountChange: ((Int) -> Void)?
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "file-shelf")

    @discardableResult
    func add(_ urls: [URL]) -> Bool {
        refresh()
        var added = 0
        var duplicates = 0
        var rejected = 0
        for rawURL in urls {
            guard Self.isLocalFile(rawURL) else { rejected += 1; continue }
            let url = rawURL.standardizedFileURL
            if files.contains(where: { $0.url == url }) { duplicates += 1; continue }
            guard files.count < Self.limit else { rejected += 1; continue }
            do {
                let values = try url.resourceValues(forKeys: [.isVolumeKey])
                guard values.isVolume != true, try url.checkResourceIsReachable() else {
                    rejected += 1
                    continue
                }
                let bookmark = try url.bookmarkData(options: .minimalBookmark,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
                files.append(ShelfFile(url: url, bookmark: bookmark))
                added += 1
            } catch {
                rejected += 1
                logger.error("Could not hold a file: \(error.localizedDescription, privacy: .private)")
            }
        }
        if rejected > 0 {
            let reason = files.count == Self.limit
                ? "The shelf holds up to \(Self.limit) items. Remove some to make room."
                : "Some items could not be added. Choose available files or folders."
            notice = ShelfNotice(text: added > 0 ? "Added \(added). \(reason)" : reason, isError: true)
        } else if added > 0 {
            notice = ShelfNotice(text: added == 1 ? "Added to your shelf." : "Added \(added) items to your shelf.")
        } else if duplicates > 0 {
            notice = ShelfNotice(text: "Already on your shelf.")
        }
        onCountChange?(files.count)
        return added > 0 || duplicates > 0
    }

    func remove(_ id: UUID) {
        files.removeAll { $0.id == id }
        onCountChange?(files.count)
    }

    func clear() {
        files.removeAll()
        notice = nil
        onCountChange?(0)
    }

    func refresh() {
        for index in files.indices {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: files[index].bookmark,
                                  options: [.withoutUI, .withoutMounting], relativeTo: nil,
                                  bookmarkDataIsStale: &stale)
                files[index].url = url.standardizedFileURL
                files[index].isAvailable = try url.checkResourceIsReachable()
            } catch {
                files[index].isAvailable = false
                logger.debug("Shelf reference unavailable: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func availableURL(for id: UUID) -> URL? {
        refresh()
        guard let file = files.first(where: { $0.id == id }), file.isAvailable else {
            notice = ShelfNotice(text: "This file is no longer available. Reconnect its drive or add it again.", isError: true)
            return nil
        }
        return file.url
    }

    func copy(_ id: UUID, to pasteboard: NSPasteboard = .general) {
        guard let url = availableURL(for: id) else { return }
        pasteboard.clearContents()
        if pasteboard.writeObjects([url as NSURL]) {
            notice = ShelfNotice(text: "File copied. Paste it into Finder or another app.")
        } else {
            notice = ShelfNotice(text: "Could not copy this file. Try again.", isError: true)
        }
    }

    func open(_ id: UUID) {
        guard let url = availableURL(for: id) else { return }
        open(url)
    }

    func open(_ url: URL) {
        guard Self.isLocalFile(url), NSWorkspace.shared.open(url) else {
            notice = ShelfNotice(text: "Could not open this file. Check that it is still available.", isError: true)
            return
        }
    }

    func reveal(_ id: UUID) {
        guard let url = availableURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    nonisolated static func isLocalFile(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
    }

    static func readFiles(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { ($0 as? URL) }.filter(isLocalFile)
    }
}
