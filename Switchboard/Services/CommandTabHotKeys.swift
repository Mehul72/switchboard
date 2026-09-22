import AppKit
import ApplicationServices
import Carbon
import OSLog

/// Dock handles Command-Tab before Carbon hotkey dispatch. Consume only the
/// claimed chords, so releasing this tap also releases the native switcher.
@MainActor
final class CommandTabHotKeys: HotKeyRegistering {
    var onEvent: ((UInt32, Bool) -> Void)?
    private var bindings: [UInt32: GlobalShortcut] = [:]
    private var pressedID: UInt32?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "command-tab")

    func register(_ shortcut: GlobalShortcut, id: UInt32) throws {
        guard shortcut.isCommandTab else { throw HotKeyError.systemReserved }
        guard !bindings.values.contains(shortcut), bindings[id] == nil else {
            throw HotKeyError.unavailable(OSStatus(eventHotKeyExistsErr))
        }
        guard AXIsProcessTrusted() else { throw HotKeyError.accessibilityRequired }
        if tap == nil { try install() }
        bindings[id] = shortcut
    }

    func unregister(id: UInt32) throws {
        bindings[id] = nil
        if pressedID == id { pressedID = nil }
        if bindings.isEmpty { stop() }
    }

    private func install() throws {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<CommandTabHotKeys>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { throw HotKeyError.eventMonitorUnavailable }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw HotKeyError.eventMonitorUnavailable
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pressedID = nil
            logger.notice("Command-Tab event tap was disabled by macOS")
            if let tap, AXIsProcessTrusted() { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyUp, event.getIntegerValueField(.keyboardEventKeycode) == kVK_Tab,
           let id = pressedID {
            pressedID = nil
            deliver(id: id, pressed: false)
            return nil
        }
        guard type == .keyDown, let key = NSEvent(cgEvent: event),
              let id = bindings.first(where: { $0.value == GlobalShortcut(event: key) })?.key,
              AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }
        pressedID = id
        deliver(id: id, pressed: true)
        return nil
    }

    private func deliver(id: UInt32, pressed: Bool) {
        // Building the preview panel can take longer than an event tap is
        // allowed to block. The queued event still checks current ownership.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.bindings[id] != nil else { return }
            self.onEvent?(id, pressed)
        }
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        pressedID = nil
    }

    deinit {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
