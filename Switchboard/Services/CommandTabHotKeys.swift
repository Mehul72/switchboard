import AppKit
import ApplicationServices
import Carbon
import OSLog
import os

/// Dock handles Command-Tab before Carbon hotkey dispatch. Consume only the
/// claimed chords, so releasing this tap also releases the native switcher.
@MainActor
final class CommandTabHotKeys: HotKeyRegistering {
    /// What a key event means to the claimed chords.
    enum KeyVerdict: Equatable {
        case pass
        case press(UInt32)
        case release(UInt32)
    }

    /// Everything the tap callback reads. The callback runs on the event tap
    /// thread, so none of it can be main-actor state.
    private struct ClaimedChords {
        var bindings: [UInt32: GlobalShortcut] = [:]
        var pressedID: UInt32?
        var tap: CFMachPort?
    }

    var onEvent: ((UInt32, Bool) -> Void)?
    private nonisolated let claimed = OSAllocatedUnfairLock<ClaimedChords>(uncheckedState: ClaimedChords())
    private var source: CFRunLoopSource?
    private nonisolated let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "command-tab")

    func register(_ shortcut: GlobalShortcut, id: UInt32) throws {
        guard shortcut.isCommandTab else { throw HotKeyError.systemReserved }
        let isTaken = claimed.withLockUnchecked { $0.bindings.values.contains(shortcut) || $0.bindings[id] != nil }
        guard !isTaken else { throw HotKeyError.unavailable(OSStatus(eventHotKeyExistsErr)) }
        guard AXIsProcessTrusted() else { throw HotKeyError.accessibilityRequired }
        if source == nil { try install() }
        claimed.withLockUnchecked { $0.bindings[id] = shortcut }
    }

    func unregister(id: UInt32) throws {
        let nothingLeft = claimed.withLockUnchecked { chords -> Bool in
            chords.bindings[id] = nil
            if chords.pressedID == id { chords.pressedID = nil }
            return chords.bindings.isEmpty
        }
        if nothingLeft { stop() }
    }

    private func install() throws {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<CommandTabHotKeys>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw HotKeyError.eventMonitorUnavailable }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw HotKeyError.eventMonitorUnavailable
        }
        claimed.withLockUnchecked { $0.tap = tap }
        self.source = source
        // Not the main run loop: every key press on the Mac waits for this
        // callback, and the main thread can be busy drawing a panel.
        EventTapThread.shared.add(source)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Pure, so the rule that decides which keys never reach other apps can
    /// be tested without a tap.
    nonisolated static func verdict(type: CGEventType, keyCode: Int64, flags: CGEventFlags,
                                    bindings: [UInt32: GlobalShortcut], pressedID: UInt32?) -> KeyVerdict {
        if type == .keyUp {
            guard keyCode == kVK_Tab, let pressedID else { return .pass }
            return .release(pressedID)
        }
        guard type == .keyDown, let keyCode = UInt32(exactly: keyCode) else { return .pass }
        let chord = GlobalShortcut(keyCode: keyCode, flags: flags)
        guard let id = bindings.first(where: { $0.value == chord })?.key else { return .pass }
        return .press(id)
    }

    /// Runs on the event tap thread. The event is held until this returns, so
    /// it only decides whether the key is claimed and hands the action itself
    /// to the main thread.
    private nonisolated func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tap = claimed.withLockUnchecked { chords -> CFMachPort? in
                chords.pressedID = nil
                return chords.tap
            }
            logger.notice("Command-Tab event tap was disabled by macOS")
            if let tap, AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let (bindings, pressedID) = claimed.withLockUnchecked { ($0.bindings, $0.pressedID) }
        switch Self.verdict(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                            flags: event.flags, bindings: bindings, pressedID: pressedID) {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .release(let id):
            claimed.withLockUnchecked { $0.pressedID = nil }
            deliver(id: id, pressed: false)
            return nil
        case .press(let id):
            guard AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }
            claimed.withLockUnchecked { $0.pressedID = id }
            deliver(id: id, pressed: true)
            return nil
        }
    }

    private nonisolated func deliver(id: UInt32, pressed: Bool) {
        // Building the preview panel takes longer than an event tap may
        // block. The queued event still checks current ownership.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.claimed.withLockUnchecked({ $0.bindings[id] != nil }) else { return }
            self.onEvent?(id, pressed)
        }
    }

    private func stop() {
        Self.tearDown(source: source, claimed: claimed)
        source = nil
    }

    /// Shared with `deinit`, which cannot call main-actor methods.
    private nonisolated static func tearDown(source: CFRunLoopSource?,
                                             claimed: OSAllocatedUnfairLock<ClaimedChords>) {
        let tap = claimed.withLockUnchecked { chords -> CFMachPort? in
            defer {
                chords.tap = nil
                chords.pressedID = nil
            }
            return chords.tap
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        // Removed on the tap thread itself, so no callback is still running,
        // and holding this object, once the source is gone.
        if let source { EventTapThread.shared.remove(source) }
        if let tap { CFMachPortInvalidate(tap) }
    }

    deinit {
        Self.tearDown(source: source, claimed: claimed)
    }
}
