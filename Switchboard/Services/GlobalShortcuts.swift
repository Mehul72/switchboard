import Carbon
import Combine
import Foundation
import OSLog

@MainActor
final class GlobalShortcuts: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: GlobalShortcut] = [:]
    @Published private(set) var errors: [ShortcutAction: String] = [:]
    @Published private(set) var recordingAction: ShortcutAction?
    /// Window bindings take common Control-Option combinations from every
    /// app, so they are only registered while window snapping is switched on.
    @Published private(set) var windowActionsEnabled = false
    @Published private(set) var switcherActionsEnabled = false
    var onAction: ((ShortcutAction) -> Void)?

    private struct Press {
        let recordingAction: ShortcutAction?
    }

    private let defaults: UserDefaults
    private let registrar: HotKeyRegistering
    private var registrations: [ShortcutAction: UInt32] = [:]
    private var presses: [UInt32: Press] = [:]
    private var nextID: UInt32 = 1
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "shortcuts")

    init(defaults: UserDefaults = .standard, registrar: HotKeyRegistering) {
        self.defaults = defaults
        self.registrar = registrar
        migrateCommandTabDefaults()
        for action in ShortcutAction.allCases {
            let key = Self.preferenceKey(for: action)
            guard let stored = defaults.object(forKey: key) else {
                bindings[action] = action.defaultShortcut
                continue
            }
            do {
                guard let data = stored as? Data else {
                    throw CocoaError(.coderReadCorrupt)
                }
                let binding = try JSONDecoder().decode(GlobalShortcut?.self, from: data)
                if let message = binding?.validationError(for: action) {
                    errors[action] = message
                } else {
                    bindings[action] = binding
                }
            } catch {
                errors[action] = "This saved shortcut is unreadable. Record a new one or restore its default."
            }
        }
        registrar.onEvent = { [weak self] id, pressed in self?.receive(id: id, pressed: pressed) }
        activateBindings()
    }

    static func preferenceKey(for action: ShortcutAction) -> String {
        "GlobalShortcut.\(action.rawValue)"
    }

    private func migrateCommandTabDefaults() {
        let marker = "WindowSwitcherCommandTabDefaultsMigrated"
        guard !defaults.bool(forKey: marker) else { return }
        for action in [ShortcutAction.switchWindow, .switchWindowBack] {
            let key = Self.preferenceKey(for: action)
            guard let data = defaults.data(forKey: key) else { continue }
            do {
                let saved = try JSONDecoder().decode(GlobalShortcut?.self, from: data)
                let old = GlobalShortcut(keyCode: UInt32(kVK_Tab),
                                         modifiers: UInt32(optionKey | (action == .switchWindowBack ? shiftKey : 0)))
                guard saved == old else { continue }
                defaults.set(try JSONEncoder().encode(action.defaultShortcut), forKey: key)
            } catch {
                logger.info("Could not migrate \(action.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        defaults.set(true, forKey: marker)
    }

    func beginRecording(_ action: ShortcutAction) {
        presses.removeAll()
        recordingAction = action
    }

    func cancelRecording() {
        if let action = recordingAction, registrations[action] != nil { errors[action] = nil }
        recordingAction = nil
        presses.removeAll()
    }

    func record(_ shortcut: GlobalShortcut?) {
        guard let action = recordingAction else { return }
        if set(shortcut, for: action) { cancelRecording() }
    }

    @discardableResult
    func set(_ shortcut: GlobalShortcut?, for action: ShortcutAction) -> Bool {
        if let shortcut {
            if let error = shortcut.validationError(for: action) {
                errors[action] = error
                return false
            }
            if let duplicate = ShortcutAction.allCases.first(where: { $0 != action && bindings[$0] == shortcut }) {
                errors[action] = "Already used by “\(duplicate.title)”. Choose another combination."
                return false
            }
        }
        if bindings[action] == shortcut, registrations[action] != nil || !isLive(action) {
            errors[action] = nil
            return true
        }
        do {
            let data = try JSONEncoder().encode(shortcut)
            if isLive(action) { try replaceRegistration(of: action, with: shortcut) }
            bindings[action] = shortcut
            defaults.set(data, forKey: Self.preferenceKey(for: action))
            errors[action] = nil
            return true
        } catch {
            errors[action] = error.localizedDescription
            logger.error("Could not update \(action.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func setWindowActionsEnabled(_ enabled: Bool) {
        guard enabled != windowActionsEnabled else { return }
        windowActionsEnabled = enabled
        guard !enabled else {
            activateBindings()
            return
        }
        deactivateBindings(in: .windows)
    }

    func setSwitcherActionsEnabled(_ enabled: Bool) {
        guard enabled != switcherActionsEnabled else { return }
        switcherActionsEnabled = enabled
        if enabled { activateBindings() }
        else { deactivateBindings(in: .windowSwitcher) }
    }

    private func deactivateBindings(in group: ShortcutAction.Group) {
        for action in ShortcutAction.allCases where action.group == group {
            // Unreadable saved bindings keep their message; registration
            // failures no longer apply once nothing is being registered.
            if bindings[action] != nil { errors[action] = nil }
            guard let id = registrations.removeValue(forKey: action) else { continue }
            presses[id] = nil
            do {
                try registrar.unregister(id: id)
            } catch {
                logger.error("Could not release \(action.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func retryUnavailable() {
        for action in registrations.keys { errors[action] = nil }
        activateBindings()
    }

    func isRegistered(_ shortcut: GlobalShortcut) -> Bool {
        registrations.keys.contains { isLive($0) && bindings[$0] == shortcut }
    }

    private func isLive(_ action: ShortcutAction) -> Bool {
        switch action.group {
        case .switchboard: return true
        case .windows: return windowActionsEnabled
        case .windowSwitcher: return switcherActionsEnabled
        }
    }

    /// Registers the replacement before releasing the old binding, so a
    /// combination another app holds leaves the working one in place.
    private func replaceRegistration(of action: ShortcutAction, with shortcut: GlobalShortcut?) throws {
        let newID = try shortcut.map { try register($0) }
        do {
            if let previousID = registrations[action] { try registrar.unregister(id: previousID) }
        } catch {
            if let newID {
                do { try registrar.unregister(id: newID) }
                catch { logger.error("Shortcut rollback failed: \(error.localizedDescription, privacy: .public)") }
            }
            throw error
        }
        presses.removeAll()
        registrations[action] = newID
    }

    private func register(_ shortcut: GlobalShortcut) throws -> UInt32 {
        let id = nextID
        nextID += 1
        try registrar.register(shortcut, id: id)
        return id
    }

    private func activateBindings() {
        for action in ShortcutAction.allCases where registrations[action] == nil && isLive(action) {
            guard let shortcut = bindings[action] else { continue }
            if let duplicate = registrations.keys.first(where: { bindings[$0] == shortcut }) {
                errors[action] = "Already used by “\(duplicate.title)”. Record another shortcut."
                continue
            }
            do {
                registrations[action] = try register(shortcut)
                errors[action] = nil
            } catch {
                errors[action] = error.localizedDescription
                logger.error("Could not activate \(action.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func receive(id: UInt32, pressed: Bool) {
        guard let action = registrations.first(where: { $0.value == id })?.key, isLive(action) else { return }
        if pressed {
            // The switcher opens while the modifier is held. Recording still
            // uses the release path so these keys cannot open a panel mid-edit.
            if action.group == .windowSwitcher, recordingAction == nil {
                onAction?(action)
                return
            }
            if presses[id] == nil { presses[id] = Press(recordingAction: recordingAction) }
            return
        }
        // Act once on release so a held key cannot repeatedly toggle a setting.
        guard let press = presses.removeValue(forKey: id),
              press.recordingAction == recordingAction else { return }
        if recordingAction != nil {
            record(bindings[action])
        } else {
            onAction?(action)
        }
    }
}
