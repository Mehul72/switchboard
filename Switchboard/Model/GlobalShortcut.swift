import AppKit
import Carbon

enum ShortcutAction: String, CaseIterable, Identifiable {
    case togglePanel, clipboard, captureText, toggleAwake
    case switchWindow, switchWindowBack, switchAppWindow, switchAppWindowBack
    case snapStepLeft, snapStepRight, snapStepUp, snapStepDown
    case snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight
    case snapLeftThird, snapCenterThird, snapRightThird, snapLeftTwoThirds, snapRightTwoThirds
    case snapMaximize, snapCenter, snapNextDisplay, snapPreviousDisplay, snapRestore

    enum Group: CaseIterable {
        case switchboard, windowSwitcher, windows

        var title: String {
            switch self {
            case .switchboard: return "Switchboard"
            case .windowSwitcher: return "Window switcher"
            case .windows: return "Windows"
            }
        }
    }

    var id: String { rawValue }

    var group: Group {
        if switcherMode != nil { return .windowSwitcher }
        return windowCommand == nil ? .switchboard : .windows
    }

    var switcherMode: (sameApp: Bool, backwards: Bool)? {
        switch self {
        case .switchWindow: return (false, false)
        case .switchWindowBack: return (false, true)
        case .switchAppWindow: return (true, false)
        case .switchAppWindowBack: return (true, true)
        default: return nil
        }
    }

    var windowCommand: WindowCommand? {
        switch self {
        case .togglePanel, .clipboard, .captureText, .toggleAwake,
             .switchWindow, .switchWindowBack, .switchAppWindow, .switchAppWindowBack: return nil
        case .snapStepLeft: return .step(.left)
        case .snapStepRight: return .step(.right)
        case .snapStepUp: return .step(.up)
        case .snapStepDown: return .step(.down)
        case .snapTopLeft: return .place(.topLeft)
        case .snapTopRight: return .place(.topRight)
        case .snapBottomLeft: return .place(.bottomLeft)
        case .snapBottomRight: return .place(.bottomRight)
        case .snapLeftThird: return .place(.leftThird)
        case .snapCenterThird: return .place(.centerThird)
        case .snapRightThird: return .place(.rightThird)
        case .snapLeftTwoThirds: return .place(.leftTwoThirds)
        case .snapRightTwoThirds: return .place(.rightTwoThirds)
        case .snapMaximize: return .place(.maximize)
        case .snapCenter: return .place(.center)
        case .snapNextDisplay: return .nextDisplay
        case .snapPreviousDisplay: return .previousDisplay
        case .snapRestore: return .restore
        }
    }

    var title: String {
        switch self {
        case .togglePanel: return "Show or hide Switchboard"
        case .clipboard: return "Open clipboard history"
        case .captureText: return "Copy text from the screen"
        case .toggleAwake: return "Toggle keep-awake"
        case .switchWindow: return "Switch to next window"
        case .switchWindowBack: return "Switch to previous window"
        case .switchAppWindow: return "Next window of current app"
        case .switchAppWindowBack: return "Previous window of current app"
        case .snapStepLeft: return "Step left through layouts"
        case .snapStepRight: return "Step right through layouts"
        case .snapStepUp: return "Step up through layouts"
        case .snapStepDown: return "Step down through layouts"
        case .snapTopLeft: return "Top-left quarter"
        case .snapTopRight: return "Top-right quarter"
        case .snapBottomLeft: return "Bottom-left quarter"
        case .snapBottomRight: return "Bottom-right quarter"
        case .snapLeftThird: return "Left third"
        case .snapCenterThird: return "Centre third"
        case .snapRightThird: return "Right third"
        case .snapLeftTwoThirds: return "Left two thirds"
        case .snapRightTwoThirds: return "Right two thirds"
        case .snapMaximize: return "Maximise"
        case .snapCenter: return "Centre"
        case .snapNextDisplay: return "Move to next display"
        case .snapPreviousDisplay: return "Move to previous display"
        case .snapRestore: return "Restore previous size"
        }
    }

    /// Most window rows describe themselves in their title; a line under each
    /// of eighteen rows would only repeat it.
    var detail: String? {
        switch self {
        case .togglePanel: return "Open the panel from any app."
        case .clipboard: return "Go straight to your recent clips."
        case .captureText: return "Select an area to recognise and copy its text."
        case .toggleAwake: return "Keep awake for one hour, or stop an active session."
        case .switchWindow: return "Keep the modifier held to browse previews; release it to switch."
        case .switchAppWindow: return "Browse only windows belonging to the frontmost app."
        case .snapStepLeft: return "Full screen, then left half, then left third. From a third, move between thirds."
        case .snapStepRight: return "Full screen, then right half, then right third. From a third, move between thirds."
        case .snapStepUp: return "Full screen from any layout. From full screen, the top half."
        case .snapStepDown: return "Top half, then full height, then bottom half."
        case .snapMaximize: return "Fill the screen without entering full screen."
        case .snapCenter: return "Keep the window's size and move it to the middle."
        case .snapRestore: return "Undo snapping and return to where the window was."
        default: return nil
        }
    }

    var defaultShortcut: GlobalShortcut {
        let panel = controlKey | optionKey | cmdKey
        let snap = controlKey | optionKey
        let binding: (key: Int, modifiers: Int)
        switch self {
        case .togglePanel: binding = (kVK_ANSI_S, panel)
        case .clipboard: binding = (kVK_ANSI_V, panel)
        case .captureText: binding = (kVK_ANSI_T, panel)
        case .toggleAwake: binding = (kVK_ANSI_A, panel)
        case .switchWindow: binding = (kVK_Tab, cmdKey)
        case .switchWindowBack: binding = (kVK_Tab, cmdKey | shiftKey)
        case .switchAppWindow: binding = (kVK_ANSI_Grave, optionKey)
        case .switchAppWindowBack: binding = (kVK_ANSI_Grave, optionKey | shiftKey)
        case .snapStepLeft: binding = (kVK_LeftArrow, snap)
        case .snapStepRight: binding = (kVK_RightArrow, snap)
        case .snapStepUp: binding = (kVK_UpArrow, snap)
        case .snapStepDown: binding = (kVK_DownArrow, snap)
        case .snapTopLeft: binding = (kVK_ANSI_U, snap)
        case .snapTopRight: binding = (kVK_ANSI_I, snap)
        case .snapBottomLeft: binding = (kVK_ANSI_J, snap)
        case .snapBottomRight: binding = (kVK_ANSI_K, snap)
        case .snapLeftThird: binding = (kVK_ANSI_D, snap)
        case .snapCenterThird: binding = (kVK_ANSI_F, snap)
        case .snapRightThird: binding = (kVK_ANSI_G, snap)
        case .snapLeftTwoThirds: binding = (kVK_ANSI_E, snap)
        case .snapRightTwoThirds: binding = (kVK_ANSI_T, snap)
        case .snapMaximize: binding = (kVK_Return, snap)
        case .snapCenter: binding = (kVK_ANSI_C, snap)
        case .snapRestore: binding = (kVK_Delete, snap)
        // Moving between displays is rarer and sits beside the panel shortcuts.
        case .snapNextDisplay: binding = (kVK_RightArrow, panel)
        case .snapPreviousDisplay: binding = (kVK_LeftArrow, panel)
        }
        return GlobalShortcut(keyCode: UInt32(binding.key), modifiers: UInt32(binding.modifiers))
    }
}

struct GlobalShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)

    var isCommandTab: Bool {
        keyCode == UInt32(kVK_Tab) && modifiers & ~UInt32(shiftKey) == UInt32(cmdKey)
    }

    func validationError(for action: ShortcutAction) -> String? {
        if isCommandTab, action.group != .windowSwitcher {
            return "Command-Tab is reserved for window switching. Choose another combination."
        }
        return validationError
    }

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
            return "Use a letter, number, punctuation, arrow, Tab, Return, Delete, Space, or F1 to F12."
        }
        guard modifiers & ~Self.modifierMask == 0 else {
            return "Use only Control, Option, Shift, and Command as modifiers."
        }
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            return "Include Control, Option, or Command."
        }
        // Command plus one key is copy, paste, save and the like in every app.
        guard modifiers != UInt32(cmdKey) || isCommandTab else {
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
        36: "Return", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "\u{0060}", 51: "Delete",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]
}
