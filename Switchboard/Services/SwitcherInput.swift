import AppKit
import Carbon

@MainActor
protocol SwitcherInputMonitoring: AnyObject {
    var onCommand: ((SwitcherInput.Command) -> Void)? { get set }
    var shouldPassShortcut: ((GlobalShortcut) -> Bool)? { get set }
    var modifiersAreHeld: Bool { get }
    func start(modifiers: CGEventFlags) -> Bool
    func stop()
}

/// Exists only during a switcher session. Global shortcut registration owns
/// opening the panel; this tap owns navigation and modifier release.
@MainActor
final class SwitcherInput: SwitcherInputMonitoring {
    enum Command: Equatable {
        case move(Int), commit, cancel, quit, click(CGPoint)
    }

    var onCommand: ((Command) -> Void)?
    var shouldPassShortcut: ((GlobalShortcut) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var modifierTimer: Timer?
    private var heldModifiers: CGEventFlags = []
    private var swallowedKeys: Set<Int64> = []

    func start(modifiers: CGEventFlags) -> Bool {
        stop()
        heldModifiers = modifiers
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<SwitcherInput>.fromOpaque(context).takeUnretainedValue().handle(type, event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // A release already queued when this tap is installed may miss its
        // callback. Check current state too, so a quick tap cannot get stuck.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.modifiersAreHeld else { return }
                self.onCommand?(.commit)
            }
        }
        modifierTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    func stop() {
        modifierTimer?.invalidate()
        modifierTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        swallowedKeys.removeAll()
    }

    var modifiersAreHeld: Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection(heldModifiers) == heldModifiers
    }

    static func command(keyCode: Int64, characters: String? = nil, flags: CGEventFlags,
                        heldModifiers: CGEventFlags = .maskAlternate) -> Command? {
        // Leave VoiceOver and other Command/Control chords to their owners.
        guard flags.intersection([.maskCommand, .maskControl]).subtracting(heldModifiers).isEmpty else { return nil }
        // Match the letter typed, as Command-Q does, so other layouts quit with their Q.
        if characters?.lowercased() == "q" { return .quit }
        switch Int(keyCode) {
        case kVK_Escape: return .cancel
        case kVK_Return, kVK_ANSI_KeypadEnter: return .commit
        case kVK_Tab: return .move(flags.contains(.maskShift) ? -1 : 1)
        case kVK_LeftArrow: return .move(-1)
        case kVK_RightArrow: return .move(1)
        default: return nil
        }
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Cancellation leaves the original window focused if macOS stops
            // delivering keys (for example when secure input becomes active).
            onCommand?(.cancel)
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged, event.flags.intersection(heldModifiers) != heldModifiers {
            onCommand?(.commit)
        } else if type == .leftMouseDown || type == .rightMouseDown {
            onCommand?(.click(event.location))
        } else if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let keyEvent = NSEvent(cgEvent: event)
            // Global registration owns configured chords, including remapped arrows and
            // Tab. Consuming them here would override the user's bindings.
            if let keyEvent, shouldPassShortcut?(GlobalShortcut(event: keyEvent)) == true {
                return Unmanaged.passUnretained(event)
            }
            if let command = Self.command(keyCode: code, characters: keyEvent?.charactersIgnoringModifiers,
                                          flags: event.flags, heldModifiers: heldModifiers) {
                swallowedKeys.insert(code)
                // Once the first app quits its cards vanish, so a held Q would
                // otherwise quit the next app too.
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if command != .quit || !isRepeat { onCommand?(command) }
                return nil
            }
        } else if type == .keyUp, swallowedKeys.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    deinit {
        modifierTimer?.invalidate()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
