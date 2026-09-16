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
                if let message = binding?.validationError {
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
            if let error = shortcut.validationError {
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
        for action in ShortcutAction.allCases where action.group == .windows {
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

    private func isLive(_ action: ShortcutAction) -> Bool {
        action.group == .switchboard || windowActionsEnabled
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
        guard let action = registrations.first(where: { $0.value == id })?.key else { return }
        if pressed {
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
