import Foundation
import SwiftUI

final class TweakStore: ObservableObject {
    let catalog = TweakCatalog.all

    @Published var search = ""
    @Published var category: Category = .dock
    @Published private(set) var pendingRestarts: Set<RestartTarget> = []

    // Raw effective values keyed by tweak id. Never derived state -- every entry
    // came out of CFPreferences.
    @Published private(set) var values: [String: Any] = [:]

    private let ledger = UndoLedger()

    init() {
        refresh()
    }

    func refresh() {
        var latest: [String: Any] = [:]
        for tweak in catalog {
            if let value = PreferenceStore.effectiveValue(domain: tweak.domain, key: tweak.key) {
                latest[tweak.id] = value
            }
        }
        values = latest
    }

    var visible: [Tweak] {
        if search.isEmpty {
            return catalog.filter { $0.category == category }
        }
        return catalog.filter { $0.matches(search: search) }
    }

    var hasUndoRecord: Bool { !ledger.isEmpty }

    // MARK: - Reading

    func isOn(_ tweak: Tweak) -> Bool {
        tweak.onValue.matches(values[tweak.id])
    }

    func selectedChoice(_ tweak: Tweak, among choices: [Choice]) -> Choice? {
        if let stored = values[tweak.id] {
            return choices.first { $0.value.matches(stored) }
        }
        // Key was never written, so the system is sitting on its own default.
        return choices.first { $0.value == tweak.onValue }
    }

    func stringValue(_ tweak: Tweak) -> String? {
        values[tweak.id] as? String
    }

    // MARK: - Writing

    func setOn(_ tweak: Tweak, _ on: Bool) {
        write(on ? tweak.onValue : tweak.offValue, to: tweak)
    }

    func select(_ value: PrefValue, for tweak: Tweak) {
        write(value, to: tweak)
    }

    private func write(_ value: PrefValue?, to tweak: Tweak) {
        ledger.capture(domain: tweak.domain, key: tweak.key)
        PreferenceStore.write(value, domain: tweak.domain, key: tweak.key)

        if let value {
            values[tweak.id] = value.propertyListValue
        } else {
            values[tweak.id] = PreferenceStore.effectiveValue(domain: tweak.domain, key: tweak.key)
        }

        if let target = tweak.restart {
            pendingRestarts.insert(target)
        }
    }

    // MARK: - Undo and apply

    func restoreDefaults() {
        pendingRestarts.formUnion(ledger.affectedTargets(in: catalog))
        ledger.restoreAll()
        refresh()
    }

    func applyPendingRestarts() {
        for target in pendingRestarts {
            SystemRestart.killall(target)
        }
        pendingRestarts.removeAll()
    }
}
