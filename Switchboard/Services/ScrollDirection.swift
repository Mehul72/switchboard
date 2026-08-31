import AppKit
import CoreGraphics

/// macOS exposes exactly one scroll-direction switch
/// (`NSGlobalDomain com.apple.swipescrolldirection`) and it governs the mouse
/// and the trackpad together, so a mouse user has to keep flipping it. This
/// leaves that setting alone and inverts only discrete wheel ticks, which the
/// trackpad never sends -- natural scrolling on the trackpad, traditional
/// scrolling on the mouse, at the same time.
final class ScrollInverter {
    private static var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isActive: Bool { Self.tap != nil }

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
        if active == isActive { return true }
        return active ? start() : stop()
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
        runLoopSource = source
        return true
    }

    @discardableResult
    private func stop() -> Bool {
        if let tap = Self.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        Self.tap = nil
        return true
    }

    private static func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS silently disables a tap that runs long or trips a security
        // check; without re-arming it the feature dies with no symptom.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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
