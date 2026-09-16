import AppKit
import ApplicationServices
import OSLog

/// Moves and resizes the focused window of the frontmost app.
final class WindowSnapper {
    enum Outcome: Equatable {
        case moved
        /// Nothing could be snapped. The reason goes to the log, not the user,
        /// because pressing a shortcut over the desktop is not a mistake.
        case nothingToMove(String)
        case needsPermission
    }

    private struct Target {
        let pid: pid_t
        let screens: [CGRect]
    }

    /// A window server call to an app that is not answering must not hold up
    /// the next snap for long.
    private static let messagingTimeoutSeconds: Float = 0.5
    /// Runs on every mouse press while snapping is on, so it gives up sooner.
    private static let hitTestTimeoutSeconds: Float = 0.15
    private static let enhancedInterfaceAttribute = "AXEnhancedUserInterface" as CFString
    private static let fullScreenAttribute = "AXFullScreen" as CFString

    /// Serial, so repeated presses land in order and the memory below is only
    /// ever touched from one thread.
    private let queue = DispatchQueue(label: "com.Mehul72.switchboard.window-snap", qos: .userInitiated)
    private var memory = SnapMemory<AXUIElement>()
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "window-snap")

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Call on the main thread: screen geometry and the frontmost app are
    /// AppKit state. The completion also runs on the main thread.
    func perform(_ command: WindowCommand, completion: @escaping (Outcome) -> Void) {
        guard Self.hasPermission else {
            completion(.needsPermission)
            return
        }
        let target: Target
        switch Self.currentTarget() {
        case .success(let found): target = found
        case .failure(let reason):
            logger.info("Snap skipped: \(reason.message, privacy: .public)")
            completion(.nothingToMove(reason.message))
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let outcome = self.apply(command, to: target)
            if case .nothingToMove(let reason) = outcome {
                self.logger.info("Snap skipped: \(reason, privacy: .public)")
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private struct SkipReason: Error {
        let message: String
    }

    private static func currentTarget() -> Result<Target, SkipReason> {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failure(SkipReason(message: "no frontmost app"))
        }
        // Accessibility requests to our own process are answered on the main
        // thread, which would be waiting on this queue for the answer.
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .failure(SkipReason(message: "Switchboard's own windows are not snapped"))
        }
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else {
            return .failure(SkipReason(message: "no displays"))
        }
        let visibleFrames = screens.map {
            WindowLayout.accessibilityRect(fromAppKit: $0.visibleFrame, primaryScreenHeight: primaryHeight)
        }
        return .success(Target(pid: app.processIdentifier, screens: visibleFrames))
    }

    private func apply(_ command: WindowCommand, to target: Target) -> Outcome {
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeoutSeconds)
        guard let window = Self.element(of: app, attribute: kAXFocusedWindowAttribute as CFString)
                ?? Self.element(of: app, attribute: kAXMainWindowAttribute as CFString) else {
            return .nothingToMove("the frontmost app has no focused window")
        }
        guard Self.value(of: window, attribute: Self.fullScreenAttribute) as? Bool != true else {
            return .nothingToMove("the window is full screen")
        }
        guard let current = Self.frame(of: window) else {
            return .nothingToMove("the window's frame could not be read")
        }

        let requested: CGRect
        let screen: CGRect
        var cell: LayoutCell?
        switch command {
        case .restore:
            guard let original = memory.takeOriginal(of: window) else {
                return .nothingToMove("the window has not been snapped")
            }
            requested = original
            screen = WindowLayout.screenIndex(for: original, among: target.screens)
                .map { target.screens[$0] } ?? original
        case .step(let direction):
            guard let index = WindowLayout.screenIndex(for: current, among: target.screens) else {
                return .nothingToMove("no displays")
            }
            screen = target.screens[index]
            let next: LayoutCell
            if let now = memory.cell(of: window, at: current) ?? WindowLayout.cell(matching: current, in: screen) {
                guard let stepped = now.stepped(direction) else {
                    return .nothingToMove("the window is at the edge of the layout map")
                }
                next = stepped
            } else {
                next = LayoutCell.starting(direction)
            }
            cell = next
            requested = WindowLayout.frame(for: next, in: screen)
        case .place, .nextDisplay, .previousDisplay:
            guard let destination = WindowLayout.destination(of: command, window: current,
                                                             screens: target.screens) else {
                return .nothingToMove("there is no display to move to")
            }
            if case .place(let placement) = command { cell = placement.cell }
            requested = destination.frame
            screen = destination.screen
        }

        return move(window, of: app, to: requested, on: screen, from: current, cell: cell,
                    remember: command != .restore)
    }

    /// Moves a window a drag found, on the snap queue so it cannot interleave
    /// with a keyboard snap of the same window. `original` is where the drag
    /// began, so Restore returns there rather than to the drop point.
    func place(_ window: AXUIElement, of pid: pid_t, to requested: CGRect, on screen: CGRect,
               from original: CGRect, completion: @escaping (Outcome) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeoutSeconds)
            let outcome = self.move(window, of: app, to: requested, on: screen, from: original,
                                    cell: WindowLayout.cell(matching: requested, in: screen), remember: true)
            if case .nothingToMove(let reason) = outcome {
                self.logger.info("Drop skipped: \(reason, privacy: .public)")
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private func move(_ window: AXUIElement, of app: AXUIElement, to requested: CGRect, on screen: CGRect,
                      from current: CGRect, cell: LayoutCell?, remember: Bool) -> Outcome {
        guard Self.isSettable(window, attribute: kAXPositionAttribute as CFString) else {
            return .nothingToMove("the window cannot be moved")
        }
        let resizable = Self.isSettable(window, attribute: kAXSizeAttribute as CFString)
        let goal = resizable
            ? requested
            : WindowLayout.anchored(current.size, within: requested, on: screen)

        let applied = withEnhancedInterfaceOff(app) { () -> CGRect? in
            // Size first so a window moving to a smaller display is not
            // clamped at its old size, then again once it is on that display.
            if resizable { setSize(goal.size, of: window) }
            guard setPosition(goal.origin, of: window) else { return nil }
            if resizable { setSize(goal.size, of: window) }
            guard let landed = Self.frame(of: window) else { return goal }
            let fitted = WindowLayout.fitted(landed, in: screen)
            if fitted.origin != landed.origin, setPosition(fitted.origin, of: window) {
                return fitted
            }
            return landed
        }
        guard let applied else { return .nothingToMove("the app refused the new position") }
        if remember {
            memory.recordSnap(of: window, from: current, to: applied, cell: cell)
        }
        return .moved
    }

    /// Chromium and Electron apps animate every frame change while this is on,
    /// which turns one snap into a slow slide that can end at the wrong size.
    private func withEnhancedInterfaceOff<Value>(_ app: AXUIElement, _ body: () -> Value) -> Value {
        guard Self.value(of: app, attribute: Self.enhancedInterfaceAttribute) as? Bool == true else {
            return body()
        }
        let disabled = AXUIElementSetAttributeValue(app, Self.enhancedInterfaceAttribute, kCFBooleanFalse)
        if disabled != .success {
            logger.error("Could not pause enhanced interface: \(disabled.rawValue)")
        }
        defer {
            let restored = AXUIElementSetAttributeValue(app, Self.enhancedInterfaceAttribute, kCFBooleanTrue)
            if restored != .success {
                logger.error("Could not restore enhanced interface: \(restored.rawValue)")
            }
        }
        return body()
    }

    @discardableResult
    private func setPosition(_ origin: CGPoint, of window: AXUIElement) -> Bool {
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success { logger.error("Setting window position failed: \(result.rawValue)") }
        return result == .success
    }

    private func setSize(_ size: CGSize, of window: AXUIElement) {
        var dimensions = size
        guard let value = AXValueCreate(.cgSize, &dimensions) else { return }
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        // Apps with a minimum size refuse some sizes; the frame read back
        // afterwards decides where the window finally sits.
        if result != .success { logger.info("Setting window size failed: \(result.rawValue)") }
    }

    /// The window under a point, with its owner and frame. Switchboard's own
    /// windows are left out for the same reason `currentTarget` skips them.
    /// Blocks on Accessibility, so call it off the main thread.
    static func window(at point: CGPoint) -> (window: AXUIElement, pid: pid_t, frame: CGRect)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, hitTestTimeoutSeconds)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let isWindow = value(of: hit, attribute: kAXRoleAttribute as CFString) as? String == kAXWindowRole
        guard let window = isWindow ? hit : element(of: hit, attribute: kAXWindowAttribute as CFString),
              let windowFrame = frame(of: window) else { return nil }
        return (window, pid, windowFrame)
    }

    private static func isSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute, &settable) == .success && settable.boolValue
    }

    private static func value(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func element(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        guard let value = value(of: element, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(of: element, attribute: kAXPositionAttribute as CFString),
              let sizeValue = value(of: element, attribute: kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
}
