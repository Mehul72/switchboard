import AppKit
import OSLog

/// Spots a deliberate back-and-forth shake in pointer samples. Each axis is
/// tracked on its own, so a diagonal or circular scribble also counts.
struct ShakeDetector {
    /// Shorter swings are hand tremor or a curved path, not a shake.
    static let minimumSwingPoints: CGFloat = 30
    /// Two quick reversals (left, right, left) are enough. The short window
    /// keeps slower back-and-forth aiming at a drop target from counting.
    static let windowSeconds: TimeInterval = 0.5
    static let reversalsNeeded = 2

    private struct Axis {
        var extreme: CGFloat?
        var direction: CGFloat = 0
        var reversals: [TimeInterval] = []

        mutating func add(_ value: CGFloat, at time: TimeInterval) -> Bool {
            guard let last = extreme else { extreme = value; return false }
            let delta = value - last
            if direction == 0 {
                if abs(delta) >= ShakeDetector.minimumSwingPoints { direction = delta > 0 ? 1 : -1; extreme = value }
                return false
            }
            if delta * direction > 0 { extreme = value; return false }
            guard abs(delta) >= ShakeDetector.minimumSwingPoints else { return false }
            direction = -direction
            extreme = value
            reversals = reversals.filter { time - $0 <= ShakeDetector.windowSeconds } + [time]
            return reversals.count >= ShakeDetector.reversalsNeeded
        }
    }

    private var x = Axis()
    private var y = Axis()

    mutating func add(_ point: CGPoint, at time: TimeInterval) -> Bool {
        let horizontal = x.add(point.x, at: time)
        let vertical = y.add(point.y, at: time)
        guard horizontal || vertical else { return false }
        self = ShakeDetector()
        return true
    }
}

/// One mouse-down in another app. Decides when a file drag asks for the shelf:
/// a shake, or pressing Shift on its own while the drag is in progress.
struct ShelfDragSession {
    enum Trigger: Equatable { case shake, shiftKey }

    private var shake = ShakeDetector()
    private var shiftWasDown: Bool
    private(set) var hasTriggered = false

    init(modifiers: NSEvent.ModifierFlags) {
        // Shift held before the drag began is part of that drag, not a request.
        shiftWasDown = Self.isShiftOnly(modifiers)
    }

    mutating func sample(_ point: CGPoint, at time: TimeInterval, modifiers: NSEvent.ModifierFlags,
                         isFileDrag: Bool) -> Trigger? {
        let shiftDown = Self.isShiftOnly(modifiers)
        defer { shiftWasDown = shiftDown }
        let shaken = shake.add(point, at: time)
        guard isFileDrag, !hasTriggered else { return nil }
        let trigger: Trigger? = shiftDown && !shiftWasDown ? .shiftKey : shaken ? .shake : nil
        if trigger != nil { hasTriggered = true }
        return trigger
    }

    private static func isShiftOnly(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection([.shift, .control, .option, .command]) == .shift
    }
}

/// Watches drags that start in other apps and opens the shelf on request.
/// Polls the pointer while the button is held instead of relying on drag
/// events, which the source app's drag loop does not always forward.
@MainActor
final class ShelfDragWatcher {
    private static let sampleSeconds: TimeInterval = 1.0 / 60
    /// Reading the drag pasteboard is a round trip to the pasteboard server.
    private static let pasteboardCheckSeconds: TimeInterval = 0.1

    var onTrigger: (_ files: [URL], _ pointer: NSPoint) -> Void = { _, _ in }
    var onDragEnded: () -> Void = {}

    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "file-shelf")
    private let pasteboard = NSPasteboard(name: .drag)
    private var monitor: Any?
    private var timer: Timer?
    private var session: ShelfDragSession?
    private var startChangeCount = 0
    private var lastPasteboardCheck: TimeInterval = 0
    private var draggedFiles: [URL] = []

    var isActive: Bool { monitor != nil }

    @discardableResult
    func start() -> Bool {
        guard monitor == nil else { return true }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        if monitor == nil { logger.error("Shelf drag monitor refused") }
        return monitor != nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        endSession()
    }

    private func mouseDown() {
        endSession()
        session = ShelfDragSession(modifiers: NSEvent.modifierFlags)
        startChangeCount = pasteboard.changeCount
        lastPasteboardCheck = 0
        draggedFiles = []
        let timer = Timer(timeInterval: Self.sampleSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            let hadFiles = !draggedFiles.isEmpty
            endSession()
            if hadFiles { onDragEnded() }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if draggedFiles.isEmpty, now - lastPasteboardCheck >= Self.pasteboardCheckSeconds {
            lastPasteboardCheck = now
            // An unchanged count means no drag has started since the mouse went down.
            if pasteboard.changeCount != startChangeCount {
                draggedFiles = FileShelf.readFiles(from: pasteboard)
            }
        }
        let pointer = NSEvent.mouseLocation
        guard session?.sample(pointer, at: now, modifiers: NSEvent.modifierFlags,
                              isFileDrag: !draggedFiles.isEmpty) != nil else { return }
        onTrigger(draggedFiles, pointer)
    }

    private func endSession() {
        timer?.invalidate()
        timer = nil
        session = nil
        draggedFiles = []
    }
}
