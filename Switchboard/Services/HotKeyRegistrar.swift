import Carbon
import Foundation
import OSLog

@MainActor
protocol HotKeyRegistering: AnyObject {
    var onEvent: ((UInt32, Bool) -> Void)? { get set }
    func register(_ shortcut: GlobalShortcut, id: UInt32) throws
    func unregister(id: UInt32) throws
}

enum HotKeyError: LocalizedError {
    case systemReserved
    case unavailable(OSStatus)
    case systemCheckFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .systemReserved:
            return "macOS uses this shortcut. Choose another combination."
        case .unavailable(let status):
            return "This shortcut could not be registered (code \(status)). It may be in use by another app."
        case .systemCheckFailed(let status):
            return "System shortcuts could not be checked (code \(status)). Try again."
        }
    }
}

@MainActor
final class HotKeyRegistrar: HotKeyRegistering {
    var onEvent: ((UInt32, Bool) -> Void)?
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    static let signature: OSType = 0x53574244
    private nonisolated static let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "shortcuts")

    func register(_ shortcut: GlobalShortcut, id: UInt32) throws {
        try checkSystemConflict(shortcut)
        try installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            throw HotKeyError.unavailable(status)
        }
        references[id] = reference
    }

    func unregister(id: UInt32) throws {
        guard let reference = references[id] else { return }
        let status = UnregisterEventHotKey(reference)
        guard status == noErr else { throw HotKeyError.unavailable(status) }
        references.removeValue(forKey: id)
    }

    private func checkSystemConflict(_ shortcut: GlobalShortcut) throws {
        var copied: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&copied)
        guard status == noErr, let copied else { throw HotKeyError.systemCheckFailed(status) }
        let entries = copied.takeRetainedValue() as NSArray
        for case let entry as NSDictionary in entries {
            guard (entry[kHISymbolicHotKeyEnabled] as? NSNumber)?.boolValue == true,
                  let code = entry[kHISymbolicHotKeyCode] as? NSNumber,
                  let flags = entry[kHISymbolicHotKeyModifiers] as? NSNumber else { continue }
            if code.uint32Value == shortcut.keyCode,
               flags.uint32Value & GlobalShortcut.modifierMask == shortcut.modifiers {
                throw HotKeyError.systemReserved
            }
        }
    }

    private func installHandlerIfNeeded() throws {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            // The application event target dispatches on the main event loop.
            return MainActor.assumeIsolated {
                let registrar = Unmanaged<HotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == HotKeyRegistrar.signature,
                      registrar.references[identifier.id] != nil else {
                    return OSStatus(eventNotHandledErr)
                }
                registrar.onEvent?(identifier.id, GetEventKind(event) == UInt32(kEventHotKeyPressed))
                return noErr
            }
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw HotKeyError.unavailable(status) }
    }

    deinit {
        for reference in references.values {
            let status = UnregisterEventHotKey(reference)
            if status != noErr { Self.logger.error("Hotkey cleanup failed: \(status)") }
        }
        if let handler {
            let status = RemoveEventHandler(handler)
            if status != noErr { Self.logger.error("Hotkey handler cleanup failed: \(status)") }
        }
    }
}
