import AppKit

extension String {
    /// Windows and classic-Mac apps put `\r\n` and `\r` on the clipboard.
    /// Counting or flattening those without folding them first either
    /// over-counts a line or leaves a stray control character in the preview.
    var normalizedLineEndings: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Counts `\n`, `\r\n` and `\r` as one line ending each, blank lines
    /// included. One pass over the bytes, because a clip can be megabytes
    /// long and the copies made by splitting it stalled the panel.
    var lineCount: Int {
        var lineEndings = 0
        var followsCarriageReturn = false
        var endsWithLineEnding = false
        var hasText = false
        for byte in utf8 {
            hasText = true
            switch byte {
            case UInt8(ascii: "\n"):
                // The second half of `\r\n` belongs to the ending already counted.
                if !followsCarriageReturn { lineEndings += 1 }
                followsCarriageReturn = false
                endsWithLineEnding = true
            case UInt8(ascii: "\r"):
                lineEndings += 1
                followsCarriageReturn = true
                endsWithLineEnding = true
            default:
                followsCarriageReturn = false
                endsWithLineEnding = false
            }
        }
        guard hasText else { return 0 }
        // A trailing line ending closes the last line rather than starting a new one.
        return endsWithLineEnding ? lineEndings : lineEndings + 1
    }
}

struct ClipEntry: Identifiable, Equatable {
    /// A collapsed row shows two lines, which this covers at any panel width.
    static let previewCharacterLimit = 300
    /// SwiftUI lays out a whole string before it draws any of it, so an
    /// expanded row holding megabytes of text froze the panel.
    static let expandedCharacterLimit = 20_000

    let id = UUID()
    let text: String
    /// PNG bytes when the clip is an image rather than text.
    let imageData: Data?
    let pixelSize: CGSize?
    let date: Date
    /// Set when Switchboard produced the text itself, so a captured or
    /// translated clip is recognisable in the list.
    var note: String?
    /// The start of the text on one line. Worked out once, with the line
    /// count, because the list redraws often and rescanning a large clip on
    /// every redraw is what made it stall.
    let preview: String
    let lineCount: Int
    let exceedsExpandedLimit: Bool

    init(text: String, imageData: Data?, pixelSize: CGSize?, date: Date, note: String?) {
        self.text = text
        self.imageData = imageData
        self.pixelSize = pixelSize
        self.date = date
        self.note = note
        preview = Self.preview(of: text)
        lineCount = text.lineCount
        let limit = text.index(text.startIndex, offsetBy: Self.expandedCharacterLimit, limitedBy: text.endIndex)
        exceedsExpandedLimit = limit != nil && limit != text.endIndex
    }

    var isImage: Bool { imageData != nil }

    var sizeLabel: String {
        guard let pixelSize else { return "Image" }
        return "Image \(Int(pixelSize.width)) by \(Int(pixelSize.height))"
    }

    /// What an expanded row lays out: the whole clip unless it is too long.
    /// Copy always puts the whole clip back.
    var expandedText: String {
        exceedsExpandedLimit ? String(text.prefix(Self.expandedCharacterLimit)) : text
    }

    private static func preview(of text: String) -> String {
        // Only the start is ever shown, so only the start is flattened.
        let firstWord = text.firstIndex { !$0.isWhitespace } ?? text.endIndex
        return String(text[firstWord...].prefix(previewCharacterLimit))
            .normalizedLineEndings
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}

/// Keeps recent text clips so something copied a few minutes ago is still
/// reachable. Deliberately memory only: a clipboard routinely holds passwords
/// and card numbers, and writing that to disk would turn a convenience into a
/// liability. Quitting Switchboard forgets everything.
final class ClipboardHistory {
    static let limit = 20

    private(set) var entries: [ClipEntry] = []
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int

    /// Password managers and clipboard tools mark their writes with these, and
    /// honouring them is the difference between a history and a leak.
    /// Images are far heavier than text, so they are capped separately.
    static let imageLimit = 8
    static let maximumImageBytes = 8 * 1024 * 1024

    /// The nspasteboard.org markers plus the private ones password managers
    /// and snippet tools publish. Same set Maccy honours.
    static let excludedTypes: Set<NSPasteboard.PasteboardType> = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
        NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword"),
        NSPasteboard.PasteboardType("net.antelle.keeweb"),
        NSPasteboard.PasteboardType("com.typeit4me.clipping"),
        NSPasteboard.PasteboardType("Pasteboard generator type")
    ]

    /// Everything `NSBitmapImageRep` can decode and Switchboard's own
    /// screenshot-format conversion can produce. Missing HEIC and JPEG here
    /// meant a converted screenshot never reached the history at all.
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png,
        NSPasteboard.PasteboardType("public.heic"),
        NSPasteboard.PasteboardType("public.jpeg"),
        .tiff
    ]

    var onChange: (() -> Void)?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    var isRecording: Bool { timer != nil }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        guard recording else {
            timer?.invalidate()
            timer = nil
            return
        }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.capture()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func clear() {
        // A copy awaiting the next poll belongs to the history being cleared.
        lastChangeCount = pasteboard.changeCount
        guard !entries.isEmpty else { return }
        entries.removeAll()
        onChange?()
    }

    func remove(_ entry: ClipEntry) {
        entries.removeAll { $0.id == entry.id }
        onChange?()
    }

    /// Drops the image a format conversion has just replaced on the
    /// clipboard. The converted copy is recorded by the next poll; keeping
    /// this one too listed a single screenshot twice.
    func forgetImage(_ imageData: Data) {
        let countBefore = entries.count
        entries.removeAll { $0.imageData == imageData }
        if entries.count != countBefore { onChange?() }
    }

    /// Puts an entry back on the clipboard without recording it again.
    @discardableResult
    func copyBack(_ entry: ClipEntry) -> Bool {
        pasteboard.clearContents()
        let ok: Bool
        if let imageData = entry.imageData {
            ok = pasteboard.setData(imageData, forType: .png)
        } else {
            ok = pasteboard.setString(entry.text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
        return ok
    }

    /// Records text Switchboard produced, so a capture shows up immediately
    /// rather than waiting for the next poll.
    func record(_ text: String, note: String?) {
        insert(text, note: note)
        lastChangeCount = pasteboard.changeCount
    }

    /// Internal so the recording rules can be exercised against a private
    /// pasteboard without waiting for the polling timer.
    func capture() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let items = pasteboard.pasteboardItems, let item = items.first else { return }
        // A writer can put its concealed marker on any item it publishes, not
        // only the first, and one marked item disqualifies the whole write.
        // The pasteboard also advertises types that are on none of its items,
        // so a marker can be missed by reading the items alone.
        let published = Set(items.flatMap(\.types)).union(pasteboard.types ?? [])
        guard published.isDisjoint(with: Self.excludedTypes) else { return }

        // Text wins when both are present: styled text carries a TIFF preview
        // alongside its string, and recording that as a picture would be wrong.
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            insert(text, note: nil)
            return
        }
        if let image = imageData(from: item) {
            insertImage(image.data, pixelSize: image.size)
        }
    }

    /// Entries always hold PNG, so the list and "Copy" have one encoding to
    /// deal with regardless of what the clipboard arrived as.
    private func imageData(from item: NSPasteboardItem) -> (data: Data, size: CGSize)? {
        for type in Self.imageTypes where item.types.contains(type) {
            guard let raw = item.data(forType: type),
                  raw.count <= Self.maximumImageBytes,
                  let rep = NSBitmapImageRep(data: raw) else { continue }
            let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            if type == .png { return (raw, size) }
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            return (png, size)
        }
        return nil
    }

    private func insertImage(_ data: Data, pixelSize: CGSize) {
        if let first = entries.first, first.imageData == data { return }
        entries.removeAll { $0.imageData == data }
        entries.insert(ClipEntry(text: "", imageData: data, pixelSize: pixelSize,
                                 date: Date(), note: nil), at: 0)
        // Trim the oldest images first so pictures cannot crowd out text.
        var seen = 0
        entries = entries.filter { entry in
            guard entry.isImage else { return true }
            seen += 1
            return seen <= Self.imageLimit
        }
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        onChange?()
    }

    private func insert(_ text: String, note: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Re-copying something already at the top should not duplicate it.
        if let first = entries.first, first.text == text {
            if note != nil, entries[0].note != note { entries[0].note = note; onChange?() }
            return
        }
        entries.removeAll { $0.text == text }
        entries.insert(ClipEntry(text: text, imageData: nil, pixelSize: nil,
                                 date: Date(), note: note), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        onChange?()
    }

    deinit { timer?.invalidate() }
}
