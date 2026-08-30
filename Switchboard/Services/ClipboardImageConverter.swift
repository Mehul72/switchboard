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
/// selected image encoding. A receiving app can still normalise pasted images.
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

    var onConversion: ((Result<ClipboardImageFormat, Error>) -> Void)?

    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var targetFormat: ClipboardImageFormat?
    private var lastChangeCount: Int
    private var isConverting = false
    private var generation = 0

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
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

                    self.pasteboard.clearContents()
                    guard self.pasteboard.writeObjects([replacement]) else {
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
