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

    func restoreAll() {
        for record in records.values {
            let domain = record["domain"] as! String
            let key = record["key"] as! String
            PreferenceStore.writeRaw(record["value"] as CFPropertyList?, domain: domain, key: key)
        }
        records.removeAll()
        flush()
    }

    /// Every restart target touched by the keys we are about to put back.
    func affectedTargets(in catalog: [Tweak]) -> Set<RestartTarget> {
        let touched = Set(records.keys)
        let tweaks = catalog.filter { touched.contains(Self.identifier(domain: $0.domain, key: $0.key)) }
        return Set(tweaks.compactMap(\.restart))
    }

    private func flush() {
        defaults.set(records, forKey: Self.storageKey)
    }

    private static func identifier(domain: String, key: String) -> String {
        "\(domain)/\(key)"
    }
}
