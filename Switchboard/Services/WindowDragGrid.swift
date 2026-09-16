import AppKit
import ApplicationServices
import OSLog

/// Shows a grid while a window is dragged with Control held, and snaps the
/// window to the cells swept over when the mouse is released.
final class WindowDragGrid {
    private struct Drag {
        let sequence: Int
        var target: (window: AXUIElement, pid: pid_t, frame: CGRect)?
        var isWindowMove = false
        var isCheckingMove = false
        var anchor: GridCell?
        var anchorScreen: CGRect?
        var current: GridCell?
    }

    /// Anything smaller is the app nudging its own frame, not the user dragging.
    private static let minimumMovePoints: CGFloat = 3

    private let snapper: WindowSnapper
    private let overlay = GridOverlay()
    /// Hit tests and move checks run for ordinary clicks too, so they get
    /// their own queue and never wait behind a slow snap.
    private let probeQueue = DispatchQueue(label: "com.Mehul72.switchboard.drag-probe", qos: .userInteractive)
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "window-snap")
    private var monitors: [Any] = []
    private var drag: Drag?
    private var nextSequence = 0

    init(snapper: WindowSnapper) {
        self.snapper = snapper
    }

    var isActive: Bool { !monitors.isEmpty }

    /// Returns false when macOS refuses an event monitor, which leaves the
    /// grid off rather than half working.
    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        guard active != isActive else { return true }
        guard active else {
            stop()
            return true
        }
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseDragged, { [weak self] event in self?.mouseDragged(controlHeld: Self.isControlOnly(event)) }),
            (.flagsChanged, { [weak self] event in self?.flagsChanged(controlHeld: Self.isControlOnly(event)) }),
            (.leftMouseUp, { [weak self] _ in self?.mouseUp() })
        ]
        for (mask, handler) in handlers {
            guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) else {
                logger.error("Drag grid monitor refused for mask \(mask.rawValue)")
                stop()
                return false
            }
            monitors.append(monitor)
        }
        return true
    }

    /// Command or Option with Control is some other gesture, not a request
    /// for the grid.
    private static func isControlOnly(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.control, .option, .command])
        return flags == .control
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        drag = nil
        overlay.hide()
    }

    private func mouseDown() {
        nextSequence += 1
        let sequence = nextSequence
        drag = Drag(sequence: sequence)
        let point = Self.pointerInAccessibilitySpace()
        probeQueue.async { [weak self] in
            let target = WindowSnapper.window(at: point)
            DispatchQueue.main.async {
                guard let self, self.drag?.sequence == sequence else { return }
                self.drag?.target = target
            }
        }
    }

    private func mouseDragged(controlHeld: Bool) {
        guard let current = drag, let target = current.target else { return }
        if current.isWindowMove {
            updateGrid(controlHeld: controlHeld)
            return
        }
        guard !current.isCheckingMove else { return }
        drag?.isCheckingMove = true
        let sequence = current.sequence
        probeQueue.async { [weak self] in
            let now = WindowSnapper.frame(of: target.window)
            DispatchQueue.main.async {
                guard let self, self.drag?.sequence == sequence else { return }
                self.drag?.isCheckingMove = false
                guard let now, Self.isMove(from: target.frame, to: now) else { return }
                self.drag?.isWindowMove = true
                self.updateGrid(controlHeld: NSEvent.modifierFlags.intersection([.control, .option, .command]) == .control)
            }
        }
    }

    /// Dragging a title bar moves a window without resizing it; dragging an
    /// edge resizes it, and a text selection moves nothing.
    private static func isMove(from start: CGRect, to now: CGRect) -> Bool {
        let moved = abs(now.minX - start.minX) >= minimumMovePoints || abs(now.minY - start.minY) >= minimumMovePoints
        return moved && WindowLayout.isClose(CGRect(origin: .zero, size: start.size),
                                            CGRect(origin: .zero, size: now.size))
    }

    private func flagsChanged(controlHeld: Bool) {
        guard drag?.isWindowMove == true else { return }
        updateGrid(controlHeld: controlHeld)
    }

    private func updateGrid(controlHeld: Bool) {
        guard controlHeld else {
            // Letting go of Control is how a drag gets out of the grid.
            drag?.anchor = nil
            drag?.anchorScreen = nil
            drag?.current = nil
            overlay.hide()
            return
        }
        let screens = Self.visibleScreens()
        let pointer = Self.pointerInAccessibilitySpace()
        guard let index = WindowLayout.screenIndex(for: CGRect(origin: pointer, size: CGSize(width: 1, height: 1)),
                                                   among: screens) else { return }
        let screen = screens[index]
        let cell = SnapGrid.cell(at: pointer, in: screen)
        // Crossing to another display starts the sweep again there.
        if drag?.anchor == nil || drag?.anchorScreen != screen {
            drag?.anchor = cell
            drag?.anchorScreen = screen
        }
        drag?.current = cell
        guard let anchor = drag?.anchor else { return }
        overlay.show(on: screen, highlighting: SnapGrid.frame(spanning: anchor, cell, in: screen),
                     primaryScreenHeight: Self.primaryScreenHeight)
    }

    private func mouseUp() {
        defer {
            drag = nil
            overlay.hide()
        }
        guard let finished = drag, let target = finished.target,
              let anchor = finished.anchor, let current = finished.current,
              let screen = finished.anchorScreen else { return }
        let requested = SnapGrid.frame(spanning: anchor, current, in: screen)
        snapper.place(target.window, of: target.pid, to: requested, on: screen, from: target.frame) { outcome in
            if case .nothingToMove = outcome { NSSound.beep() }
        }
    }

    private static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    private static func pointerInAccessibilitySpace() -> CGPoint {
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x, y: primaryScreenHeight - location.y)
    }

    private static func visibleScreens() -> [CGRect] {
        NSScreen.screens.map {
            WindowLayout.accessibilityRect(fromAppKit: $0.visibleFrame, primaryScreenHeight: primaryScreenHeight)
        }
    }
}

/// A click-through panel over one display's usable area.
private final class GridOverlay {
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Switchboard is never the active app during someone else's drag.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = canvas
        panel.setAccessibilityElement(false)
        return panel
    }()
    private let canvas = GridCanvas()

    func show(on screen: CGRect, highlighting highlight: CGRect, primaryScreenHeight: CGFloat) {
        let frame = WindowLayout.accessibilityRect(fromAppKit: screen, primaryScreenHeight: primaryScreenHeight)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        canvas.screen = screen
        canvas.highlight = highlight
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

private final class GridCanvas: NSView {
    var screen: CGRect = .zero { didSet { needsDisplay = true } }
    var highlight: CGRect = .zero { didSet { needsDisplay = true } }

    /// Matches Accessibility's downward y, so grid frames draw without flipping.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        NSColor.black.withAlphaComponent(0.1).setFill()
        bounds.fill()

        NSColor.white.withAlphaComponent(0.45).setStroke()
        for column in 0..<SnapGrid.columns {
            for row in 0..<SnapGrid.rows {
                let cell = GridCell(column: column, row: row)
                let outline = NSBezierPath(rect: local(SnapGrid.frame(spanning: cell, cell, in: screen)).insetBy(dx: 0.5, dy: 0.5))
                outline.lineWidth = 1
                outline.stroke()
            }
        }

        let selection = NSBezierPath(roundedRect: local(highlight).insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10)
        accent.withAlphaComponent(0.3).setFill()
        selection.fill()
        accent.setStroke()
        selection.lineWidth = 3
        selection.stroke()
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screen.minX, dy: -screen.minY)
    }
}
