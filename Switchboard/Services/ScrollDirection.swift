import AppKit
import CoreGraphics

/// macOS exposes exactly one scroll-direction switch
/// (`NSGlobalDomain com.apple.swipescrolldirection`) and it governs the mouse
/// and the trackpad together, so a mouse user has to keep flipping it. This
/// leaves that setting alone and inverts only discrete wheel ticks, which the
/// trackpad never sends -- natural scrolling on the trackpad, traditional
/// scrolling on the mouse, at the same time.
final class ScrollInverter {
    /// The event-tap callback is a C function pointer with no context, so the
    /// port it has to re-arm lives here. The run loop source is stored beside
    /// it rather than on the instance, so a stop always tears down exactly
    /// what the matching start put in place.
    private static var tap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?

    /// macOS can disable a tap without sending the `tapDisabled` event that
    /// would re-arm it, which leaves the feature dead with the toggle still
    /// showing on. Nothing else notices, so this is the only signal.
    private static let healthCheckInterval: TimeInterval = 5
    private static let defaultsKey = "MouseScrollInvertedEnabled"

    private let defaults: UserDefaults
    private var healthTimer: Timer?

    var isActive: Bool { Self.tap != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        resumeIfPermitted()
    }

    /// The event tap is a system-wide input hook, so macOS gates it behind
    /// Accessibility. Granting is a one-time trip to System Settings.
    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        defer { defaults.set(isActive, forKey: Self.defaultsKey) }
        if active == isActive { return true }
        return active ? start() : stop()
    }

    /// Accessibility is granted in System Settings long after launch, and
    /// revoking it kills the tap. Either way the stored preference is what the
    /// user asked for, so it survives and the tap follows the permission.
    @discardableResult
    func resumeIfPermitted() -> Bool {
        switch AccessibilityResumeStep.next(preferenceOn: defaults.bool(forKey: Self.defaultsKey),
                                            permitted: Self.hasPermission,
                                            running: isActive) {
        case .start: return start()
        case .stop: _ = stop(); return false
        case .leaveAlone: return isActive
        }
    }

    private func start() -> Bool {
        guard Self.hasPermission else { return false }

        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in ScrollInverter.handle(type, event) },
            userInfo: nil
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Self.tap = tap
        Self.runLoopSource = source
        startHealthChecks()
        return true
    }

    @discardableResult
    private func stop() -> Bool {
        healthTimer?.invalidate()
        healthTimer = nil
        if let tap = Self.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Dropping the last reference is not enough; without this the
            // mach port stays live for the rest of the session.
            CFMachPortInvalidate(tap)
        }
        if let source = Self.runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        Self.runLoopSource = nil
        Self.tap = nil
        return true
    }

    private func startHealthChecks() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: Self.healthCheckInterval, repeats: true) { [weak self] _ in
            self?.reArmIfDisabled()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func reArmIfDisabled() {
        guard let tap = Self.tap else { return }
        // A revoked Accessibility grant cannot be re-armed, so drop the tap
        // instead of retrying it forever. The preference stays put and the
        // next grant brings the feature back.
        guard Self.hasPermission else {
            _ = stop()
            return
        }
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private static func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS silently disables a tap that runs long or trips a security
        // check; without re-arming it the feature dies with no symptom.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        // A trackpad (and a Magic Mouse gesture) sends continuous deltas that
        // carry a scroll or momentum phase; a wheel sends discrete ticks with
        // neither. Only the wheel gets flipped.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        // Writing the line delta makes Core Graphics recompute the fixed-point
        // and point deltas from it, so all three have to be read before the
        // first write. Negating them from live values afterwards flips the
        // already-flipped fields back, which leaves the point delta -- the one
        // AppKit reads for `scrollingDeltaY` -- pointing the original way.
        // Writing the line delta first, then restoring the device's own
        // fixed-point and point deltas negated, also keeps their full
        // resolution instead of the coarser values derived from whole lines.
        let axes: [(unit: CGEventField, fixed: CGEventField, point: CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        ]
        for axis in axes {
            let unit = event.getIntegerValueField(axis.unit)
            let fixed = event.getDoubleValueField(axis.fixed)
            let point = event.getIntegerValueField(axis.point)
            event.setIntegerValueField(axis.unit, value: -unit)
            event.setDoubleValueField(axis.fixed, value: -fixed)
            event.setIntegerValueField(axis.point, value: -point)
        }
        return Unmanaged.passUnretained(event)
    }

    deinit { stop() }
}
