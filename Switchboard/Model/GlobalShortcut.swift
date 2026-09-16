import AppKit
import Carbon

enum ShortcutAction: String, CaseIterable, Identifiable {
    case togglePanel, clipboard, captureText, toggleAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togglePanel: return "Show or hide Switchboard"
        case .clipboard: return "Open clipboard history"
        case .captureText: return "Copy text from the screen"
        case .toggleAwake: return "Toggle keep-awake"
        }
    }

    var detail: String {
        switch self {
        case .togglePanel: return "Open the panel from any app."
        case .clipboard: return "Go straight to your recent clips."
        case .captureText: return "Select an area to recognise and copy its text."
        case .toggleAwake: return "Keep awake for one hour, or stop an active session."
        }
    }

    var defaultShortcut: GlobalShortcut {
        let key: Int
        switch self {
        case .togglePanel: key = kVK_ANSI_S
        case .clipboard: key = kVK_ANSI_V
        case .captureText: key = kVK_ANSI_T
        case .toggleAwake: key = kVK_ANSI_A
        }
        return GlobalShortcut(keyCode: UInt32(key), modifiers: UInt32(controlKey | optionKey | cmdKey))
    }
}

struct GlobalShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        // Arrow and function-key events carry Fn even without the modifier held.
        if event.modifierFlags.contains(.function), keyCode < 96 {
            flags |= UInt32(kEventKeyModifierFnMask)
        }
        modifiers = flags
    }

    var validationError: String? {
        guard Self.keyNames[keyCode] != nil else {
            return "Use a letter, number, punctuation, arrow, Space, or F1 to F12."
        }
        guard modifiers & ~Self.modifierMask == 0 else {
            return "Use only Control, Option, Shift, and Command as modifiers."
        }
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            return "Include Control, Option, or Command."
        }
        // Command plus one key is copy, paste, save and the like in every app.
        guard modifiers != UInt32(cmdKey) else {
            return "Add another modifier to Command, or use Control or Option."
        }
        return nil
    }

    var label: String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        return prefix + keyLabel
    }

    var spokenLabel: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        return (parts + [keyLabel]).joined(separator: " ")
    }

    private var keyLabel: String {
        let fallback = Self.keyNames[keyCode] ?? "Unknown key"
        guard fallback.count == 1,
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return fallback }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return fallback }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 49: "Space", 50: "\u{0060}",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]
}
