import Combine
import Foundation
import OSLog

@MainActor
final class GlobalShortcuts: ObservableObject {
    @Published private(set) var bindings: [ShortcutAction: GlobalShortcut] = [:]
    @Published private(set) var errors: [ShortcutAction: String] = [:]
    @Published private(set) var recordingAction: ShortcutAction?
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
        if bindings[action] == shortcut, registrations[action] != nil {
            errors[action] = nil
            return true
        }
        do {
            let data = try JSONEncoder().encode(shortcut)
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

    func retryUnavailable() {
        for action in registrations.keys { errors[action] = nil }
        activateBindings()
    }

    private func register(_ shortcut: GlobalShortcut) throws -> UInt32 {
        let id = nextID
        nextID += 1
        try registrar.register(shortcut, id: id)
        return id
    }

    private func activateBindings() {
        for action in ShortcutAction.allCases where registrations[action] == nil {
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
