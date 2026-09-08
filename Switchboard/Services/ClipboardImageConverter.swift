import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ClipboardImageFormat: String, Equatable {
    case png
    case jpeg = "jpg"
    case heic

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }

    static func preferenceValue(_ value: String) -> ClipboardImageFormat? {
        switch value.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        default: return nil
        }
    }
}

/// Current macOS clipboard screenshots arrive as one `public.png` item even
/// when the saved-file preference is JPEG or HEIC. While clipboard capture is
/// enabled, this watches for that shape and republishes the bytes using the
/// selected image encoding, alongside a real file in that encoding.
///
/// The file flavour is what makes the setting visible. macOS transcodes image
/// flavours on demand, so an app that pastes through `NSImage` gets raw pixels
/// and re-encodes them, almost always as PNG. An app that accepts a pasted
/// file keeps the bytes and the extension it was handed.
final class ClipboardImageConverter {
    enum ConversionError: LocalizedError {
        case clipboardAccessDenied
        case clipboardReadFailed
        case decodeFailed
        case encodeFailed(ClipboardImageFormat)
        case pasteboardWriteFailed

        var errorDescription: String? {
            switch self {
            case .clipboardAccessDenied:
                return "Allow Switchboard to access the clipboard in System Settings."
            case .clipboardReadFailed:
                return "The clipboard image could not be read. Allow Clipboard access, then take a new screenshot."
            case .decodeFailed:
                return "The clipboard screenshot could not be decoded."
            case .encodeFailed(let format):
                return "The clipboard screenshot could not be converted to \(format.label)."
            case .pasteboardWriteFailed:
                return "The converted screenshot could not be returned to the clipboard."
            }
        }
    }

    /// A pasted file URL stays useful only while the file behind it exists, so
    /// recent conversions are kept rather than deleted on the next capture.
    static let spooledFileLimit = 5

    var onConversion: ((Result<ClipboardImageFormat, Error>) -> Void)?

    private let pasteboard: NSPasteboard
    private let spoolDirectory: URL
    private var timer: Timer?
    private var targetFormat: ClipboardImageFormat?
    private var lastChangeCount: Int
    private var isConverting = false
    private var generation = 0

    init(pasteboard: NSPasteboard = .general, spoolDirectory: URL? = nil) {
        self.pasteboard = pasteboard
        self.spoolDirectory = spoolDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory(),
                                                    isDirectory: true)
            .appendingPathComponent("Switchboard", isDirectory: true)
            .appendingPathComponent("ClipboardScreenshots", isDirectory: true)
        self.lastChangeCount = pasteboard.changeCount
    }

    var isActive: Bool { timer != nil }

    func configure(enabled: Bool, format rawFormat: String?) {
        guard enabled,
              let rawFormat,
              let format = ClipboardImageFormat.preferenceValue(rawFormat),
              format != .png else {
            if isActive || targetFormat != nil || isConverting { stop() }
            return
        }

        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            if isActive || targetFormat != nil || isConverting { stop() }
            onConversion?(.failure(ConversionError.clipboardAccessDenied))
            return
        }
        guard targetFormat != format || timer == nil else { return }

        stop()
        targetFormat = format
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.processNewClipboardContents()
        }
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        targetFormat = nil
        isConverting = false
    }

    /// Internal so the format conversion can be exercised with a private
    /// pasteboard in diagnostics without waiting for the polling timer.
    func processNewClipboardContents() {
        guard !isConverting,
              let targetFormat,
              targetFormat != .png else { return }

        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            stop()
            onConversion?(.failure(ConversionError.clipboardAccessDenied))
            return
        }

        let observedChangeCount = pasteboard.changeCount
        guard observedChangeCount != lastChangeCount else { return }

        guard let items = pasteboard.pasteboardItems else {
            handleUnreadableClipboard(changeCount: observedChangeCount)
            return
        }
        guard items.count == 1,
              let item = items.first,
              item.types == [.png] else {
            lastChangeCount = observedChangeCount
            return
        }
        guard let pngData = item.data(forType: .png) else {
            handleUnreadableClipboard(changeCount: observedChangeCount)
            return
        }
        lastChangeCount = observedChangeCount

        isConverting = true
        let conversionGeneration = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.encode(pngData, as: targetFormat)
            DispatchQueue.main.async {
                guard let self,
                      self.generation == conversionGeneration else { return }
                self.isConverting = false
                guard self.targetFormat == targetFormat,
                      self.pasteboard.changeCount == observedChangeCount else { return }

                switch result {
                case .success(let data):
                    let replacement = NSPasteboardItem()
                    let original = NSPasteboardItem()
                    let type = NSPasteboard.PasteboardType(targetFormat.contentType.identifier)
                    guard replacement.setData(data, forType: type),
                          original.setData(pngData, forType: .png) else {
                        self.onConversion?(.failure(ConversionError.pasteboardWriteFailed))
                        return
                    }
                    guard self.pasteboard.changeCount == observedChangeCount else { return }

                    // The image data alone still pastes, so a spool failure
                    // degrades the result rather than failing the conversion.
                    let spooledFile = self.spool(data, as: targetFormat)
                    if let spooledFile {
                        _ = replacement.setString(spooledFile.absoluteString, forType: .fileURL)
                    }

                    self.pasteboard.clearContents()
                    guard self.pasteboard.writeObjects([replacement]) else {
                        self.discardSpooledFile(spooledFile)
                        self.pasteboard.clearContents()
                        _ = self.pasteboard.writeObjects([original])
                        self.lastChangeCount = self.pasteboard.changeCount
                        self.onConversion?(.failure(ConversionError.pasteboardWriteFailed))
                        return
                    }
                    self.lastChangeCount = self.pasteboard.changeCount
                    self.onConversion?(.success(targetFormat))
                case .failure(let error):
                    self.onConversion?(.failure(error))
                }
            }
        }
    }

    /// Never retry a denied/transient read against the same pasteboard change:
    /// on newer macOS versions that could repeatedly ask for Clipboard access.
    private func handleUnreadableClipboard(changeCount: Int) {
        lastChangeCount = changeCount
        if #available(macOS 15.4, *), pasteboard.accessBehavior == .alwaysDeny {
            stop()
            onConversion?(.failure(ConversionError.clipboardAccessDenied))
        } else {
            onConversion?(.failure(ConversionError.clipboardReadFailed))
        }
    }

    /// Writes the converted bytes where a pasting app can pick them up as a
    /// file. Returns nil when the spool is unusable; the caller carries on
    /// with the image flavour only.
    private func spool(_ data: Data, as format: ClipboardImageFormat) -> URL? {
        let files = FileManager.default
        do {
            try files.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let stamp = Self.fileNameStamp.string(from: Date())
        var destination = spoolDirectory
            .appendingPathComponent("Screenshot \(stamp)")
            .appendingPathExtension(format.rawValue)
        // Two captures inside the same second must not collide, and
        // overwriting would change what an earlier paste resolves to.
        var attempt = 2
        while files.fileExists(atPath: destination.path) {
            destination = spoolDirectory
                .appendingPathComponent("Screenshot \(stamp) (\(attempt))")
                .appendingPathExtension(format.rawValue)
            attempt += 1
        }

        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            return nil
        }
        pruneSpool(keeping: destination)
        return destination
    }

    private func discardSpooledFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Keeps the spool from growing without bound while leaving enough recent
    /// files that a paste from a few screenshots ago still resolves.
    private func pruneSpool(keeping newest: URL) {
        let files = FileManager.default
        guard let contents = try? files.contentsOfDirectory(
            at: spoolDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let byNewestFirst = contents.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }
        for stale in byNewestFirst.dropFirst(Self.spooledFileLimit)
        where stale.standardizedFileURL != newest.standardizedFileURL {
            try? files.removeItem(at: stale)
        }
    }

    /// Fixed locale and a path-safe time separator, so the name never picks up
    /// a slash or a locale's ordering from the user's region settings.
    private static let fileNameStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    private static func encode(_ pngData: Data,
                               as format: ClipboardImageFormat) -> Result<Data, Error> {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .failure(ConversionError.decodeFailed)
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            return .failure(ConversionError.encodeFailed(format))
        }

        var properties: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        // A screenshot from a Retina display carries a 2x DPI. Re-encoding
        // without it leaves the image tagged at 72 DPI, so every app pastes it
        // at twice its intended size.
        for key in [kCGImagePropertyDPIWidth,
                    kCGImagePropertyDPIHeight,
                    kCGImagePropertyOrientation] {
            if let value = sourceProperties?[key] { properties[key] = value }
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return .failure(ConversionError.encodeFailed(format))
        }
        return .success(output as Data)
    }

    deinit { stop() }
}
