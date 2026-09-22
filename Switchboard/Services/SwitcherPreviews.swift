import AppKit
import OSLog

/// Keeps small window thumbnails between openings so cards can show them at
/// once, and refreshes only the cards the panel asks for, one capture at a time.
/// Nothing is written to disk.
@MainActor
final class SwitcherPreviews {
    typealias CaptureRunner = (UInt32, @escaping (CGImage?) -> Void) -> Void

    /// Reopening the switcher within this many seconds reuses the thumbnail.
    static let freshSeconds: TimeInterval = 2
    /// About twice a card's width, so a Retina card stays sharp.
    nonisolated static let thumbnailPixels: CGFloat = 400

    var onPreview: ((UInt32, NSImage) -> Void)?
    private let capture: CaptureRunner
    private let clock: () -> TimeInterval
    private let limit: Int
    private var thumbnails: [UInt32: (image: NSImage, capturedAt: TimeInterval)] = [:]
    private var pending: [UInt32] = []
    private var capturing: UInt32?
    /// Changes on discard, so a capture that was running cannot repopulate the cache.
    private var generation = 0

    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias CaptureFunction = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
    // ScreenCaptureKit refuses windows on other Spaces, minimized windows and
    // hidden apps. WindowServer still holds their contents and hands them over here.
    private nonisolated static let mainConnection = privateSymbol("CGSMainConnectionID", as: ConnectionFunction.self)
    private nonisolated static let captureWindows = privateSymbol("CGSHWCaptureWindowList", as: CaptureFunction.self)
    private nonisolated static let captureQueue = DispatchQueue(label: "com.Mehul72.switchboard.window-previews", qos: .userInitiated)
    private nonisolated static let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "window-previews")

    init(capture: CaptureRunner? = nil, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         limit: Int = 48) {
        self.capture = capture ?? Self.captureInBackground
        self.clock = clock
        self.limit = limit
    }

    func thumbnails(for ids: [UInt32]) -> [UInt32: NSImage] {
        var known: [UInt32: NSImage] = [:]
        for id in ids { known[id] = thumbnails[id]?.image }
        return known
    }

    /// `first` puts the capture ahead of the queue, for the selected card.
    func request(_ id: UInt32, first: Bool = false) {
        guard capturing != id else { return }
        if let known = thumbnails[id], clock() - known.capturedAt < Self.freshSeconds { return }
        pending.removeAll { $0 == id }
        if first { pending.insert(id, at: 0) } else { pending.append(id) }
        startNext()
    }

    /// The panel closed. A capture already running still lands in the cache.
    func cancelRequests() { pending.removeAll() }

    func prune(keeping ids: Set<UInt32>) {
        thumbnails = thumbnails.filter { ids.contains($0.key) }
        pending.removeAll { !ids.contains($0) }
    }

    func discardAll() {
        generation += 1
        thumbnails.removeAll()
        pending.removeAll()
        capturing = nil
    }

    private func startNext() {
        guard capturing == nil, !pending.isEmpty else { return }
        let id = pending.removeFirst()
        capturing = id
        let generation = generation
        capture(id) { [weak self] image in
            self?.finish(id, image: image, generation: generation)
        }
    }

    private func finish(_ id: UInt32, image: CGImage?, generation: Int) {
        guard generation == self.generation else { return }
        capturing = nil
        if let image {
            let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            thumbnails[id] = (preview, clock())
            if thumbnails.count > limit, let oldest = thumbnails.min(by: { $0.value.capturedAt < $1.value.capturedAt })?.key {
                thumbnails[oldest] = nil
            }
            onPreview?(id, preview)
        }
        startNext()
    }

    private nonisolated static func captureInBackground(_ id: UInt32, finish: @escaping (CGImage?) -> Void) {
        captureQueue.async {
            let image = thumbnail(of: id)
            DispatchQueue.main.async { finish(image) }
        }
    }

    nonisolated static func thumbnail(of windowID: UInt32) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let mainConnection, let captureWindows else {
            logger.notice("Window capture unavailable; cards keep their app icons")
            return nil
        }
        var id = windowID
        let ignoreClipShape: UInt32 = 1 << 11, nominalResolution: UInt32 = 1 << 9
        guard let full = (captureWindows(mainConnection(), &id, 1, ignoreClipShape | nominalResolution)?
                            .takeRetainedValue() as? [CGImage])?.first, full.width > 0, full.height > 0 else {
            logger.info("Preview unavailable for window \(windowID)")
            return nil
        }
        // Scale down straight away so only the small copy outlives this call.
        let scale = min(1, thumbnailPixels / CGFloat(max(full.width, full.height)))
        let width = max(1, Int(CGFloat(full.width) * scale)), height = max(1, Int(CGFloat(full.height) * scale))
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
