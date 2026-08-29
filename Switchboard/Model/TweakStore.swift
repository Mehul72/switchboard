import Foundation
import SwiftUI

struct StoreNotice: Equatable {
    enum Kind { case success, information, error }
    let kind: Kind
    let message: String
}

final class TweakStore: ObservableObject {
    let catalog = TweakCatalog.all

    @Published var search = ""
    @Published var category: Category = .everyday
    @Published private(set) var pendingRestarts: Set<RestartTarget> = []
    @Published private(set) var values: [String: Any] = [:]
    @Published private(set) var customStates: [String: Bool] = [:]
    @Published var notice: StoreNotice?

    private let ledger = UndoLedger()
    private let awake = AwakeController()

    init() {
        refresh()
    }

    func refresh() {
        var latest: [String: Any] = [:]
        for tweak in catalog {
            guard let preference = tweak.preference else { continue }
            if let value = PreferenceStore.effectiveValue(domain: preference.domain, key: preference.key) {
                latest[tweak.id] = value
            }
        }
        values = latest
        customStates["everyday.keep-awake"] = awake.isActive
    }

    var visible: [Tweak] {
        if search.isEmpty {
            return catalog.filter { $0.category == category }
        }
        return catalog.filter { $0.matches(search: search) }
    }

    var visibleCategories: [Category] {
        search.isEmpty ? [category] : Category.allCases.filter { category in
            visible.contains { $0.category == category }
        }
    }

    var hasUndoRecord: Bool { !ledger.isEmpty }
    var canRestoreOriginalSettings: Bool { hasUndoRecord || awake.isActive }

    func tweaks(in category: Category) -> [Tweak] {
        visible.filter { $0.category == category }
    }

    func isOn(_ tweak: Tweak) -> Bool {
        switch tweak.behavior {
        case .preference(let preference):
            return preference.onValue.matches(values[tweak.id])
        case .keepAwake:
            return customStates[tweak.id] ?? false
        case .plainTextClipboard:
            return false
        }
    }

    func selectedChoice(_ tweak: Tweak, among choices: [Choice]) -> Choice? {
        if let stored = values[tweak.id] {
            return choices.first { $0.value.matches(stored) }
        }
        return choices.first { $0.value == tweak.preference?.onValue }
    }

    func stringValue(_ tweak: Tweak) -> String? {
        values[tweak.id] as? String
    }

    func setOn(_ tweak: Tweak, _ on: Bool) {
        switch tweak.behavior {
        case .preference(let preference):
            write(on ? preference.onValue : preference.offValue, to: tweak, preference: preference)
        case .keepAwake:
            let applied = awake.setActive(on)
            customStates[tweak.id] = awake.isActive
            notice = StoreNotice(kind: applied ? .success : .error,
                                 message: applied
                                    ? (on ? "Your Mac will stay awake while Switchboard is running." : "Normal sleep settings are active again.")
                                    : "macOS could not change the sleep assertion.")
        case .plainTextClipboard:
            break
        }
    }

    func select(_ value: PrefValue, for tweak: Tweak) {
        guard let preference = tweak.preference else { return }
        if case .folder = tweak.control,
           case .string(let path) = value {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: path) else {
                notice = StoreNotice(kind: .error,
                                     message: "Choose a folder that macOS can write to.")
                return
            }
        }
        write(value, to: tweak, preference: preference)
    }

    func perform(_ tweak: Tweak) {
        guard case .plainTextClipboard = tweak.behavior else { return }
        let success = ClipboardCleaner.makePlainText()
        notice = StoreNotice(kind: success ? .success : .information,
                             message: success
                                ? "Clipboard formatting removed."
                                : "Copy some text first, then try again.")
    }

    private func write(_ value: PrefValue?, to tweak: Tweak, preference: PreferenceSpec) {
        ledger.capture(domain: preference.domain, key: preference.key)
        let synchronized = PreferenceStore.write(value,
                                                  domain: preference.domain,
                                                  key: preference.key)
        reread(tweak, preference: preference)

        let accepted: Bool
        if let value {
            accepted = value.matches(values[tweak.id])
        } else {
            accepted = PreferenceStore.storedValue(domain: preference.domain,
                                                    key: preference.key) == nil
        }

        guard synchronized && accepted else {
            notice = StoreNotice(kind: .error,
                                 message: "macOS did not accept this change.")
            return
        }

        if let target = preference.restart {
            pendingRestarts.insert(target)
            notice = StoreNotice(kind: .information,
                                 message: "Saved. Restart \(target.label) to apply it.")
        } else {
            notice = StoreNotice(kind: .success,
                                 message: tweak.successMessage ?? "Change applied.")
        }
    }

    private func reread(_ tweak: Tweak, preference: PreferenceSpec) {
        if let current = PreferenceStore.effectiveValue(domain: preference.domain, key: preference.key) {
            values[tweak.id] = current
        } else {
            values.removeValue(forKey: tweak.id)
        }
    }

    func restoreDefaults() {
        guard canRestoreOriginalSettings else { return }
        pendingRestarts.formUnion(ledger.affectedTargets(in: catalog))
        let preferencesRestored = ledger.restoreAll()
        let awakeRestored = awake.setActive(false)
        let restored = preferencesRestored && awakeRestored
        refresh()
        notice = StoreNotice(kind: restored ? .success : .error,
                             message: restored
                                ? "Original settings restored."
                                : "Some original settings could not be restored.")
    }

    func applyPendingRestarts() {
        var completed: Set<RestartTarget> = []
        for target in pendingRestarts where SystemRestart.killall(target) {
            completed.insert(target)
        }
        pendingRestarts.subtract(completed)
        refresh()

        if pendingRestarts.isEmpty {
            notice = StoreNotice(kind: .success, message: "Changes are now active.")
        } else {
            notice = StoreNotice(kind: .error,
                                 message: "A system service could not be restarted. Try again.")
        }
    }
}
