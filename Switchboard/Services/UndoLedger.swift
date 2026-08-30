import Foundation

/// Remembers what every key looked like before Switchboard first wrote to it,
/// including the common case of the key not existing at all.
final class UndoLedger {
    private static let storageKey = "OriginalValues"

    private let defaults: UserDefaults
    private var records: [String: [String: Any]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.records = defaults.dictionary(forKey: Self.storageKey) as? [String: [String: Any]] ?? [:]
    }

    var isEmpty: Bool { records.isEmpty }

    func capture(domain: String, key: String) {
        let id = Self.identifier(domain: domain, key: key)
        guard records[id] == nil else { return }

        var record: [String: Any] = ["domain": domain, "key": key]
        if let original = PreferenceStore.storedValue(domain: domain, key: key) {
            record["value"] = original
        }
        records[id] = record
        flush()
    }

    @discardableResult
    func restoreAll() -> Bool {
        var failed = false
        for (id, record) in Array(records) {
            guard let domain = record["domain"] as? String,
                  let key = record["key"] as? String else {
                records.removeValue(forKey: id)
                continue
            }
            if PreferenceStore.writeRaw(record["value"] as CFPropertyList?, domain: domain, key: key) {
                records.removeValue(forKey: id)
            } else {
                failed = true
            }
        }
        flush()
        return !failed
    }

    /// Restores one retired tweak without disturbing the rest of the user's
    /// undo history. Used when a catalog item is replaced with new behaviour.
    @discardableResult
    func restore(domain: String, key: String) -> Bool {
        let id = Self.identifier(domain: domain, key: key)
        guard let record = records[id] else { return true }
        guard let recordedDomain = record["domain"] as? String,
              let recordedKey = record["key"] as? String else {
            records.removeValue(forKey: id)
            flush()
            return true
        }
        guard PreferenceStore.writeRaw(record["value"] as CFPropertyList?,
                                       domain: recordedDomain,
                                       key: recordedKey) else { return false }
        records.removeValue(forKey: id)
        flush()
        return true
    }

    /// Every restart target touched by the keys we are about to put back.
    func affectedTargets(in catalog: [Tweak]) -> Set<RestartTarget> {
        let catalogTargets: [String: RestartTarget] = Dictionary(uniqueKeysWithValues: catalog.compactMap { tweak in
            guard let preference = tweak.preference,
                  let target = preference.restart else { return nil }
            return (Self.identifier(domain: preference.domain, key: preference.key), target)
        })

        return Set(records.compactMap { id, record in
            if let target = catalogTargets[id] { return target }
            switch record["domain"] as? String {
            case "com.apple.dock": return .dock
            case "com.apple.finder": return .finder
            default: return nil
            }
        })
    }

    private func flush() {
        if records.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(records, forKey: Self.storageKey)
        }
    }

    private static func identifier(domain: String, key: String) -> String {
        "\(domain)/\(key)"
    }
}
