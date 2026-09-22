import Foundation

// CFPreferences addresses the global domain by a sentinel app ID rather than
// the "NSGlobalDomain" name that `defaults` accepts.
private func appID(for domain: String) -> CFString {
    domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : domain as CFString
}

enum PreferenceStore {
    static func effectiveValue(domain: String, key: String) -> Any? {
        if domain == "NSGlobalDomain" {
            return CFPreferencesCopyValue(key as CFString,
                                          kCFPreferencesAnyApplication,
                                          kCFPreferencesCurrentUser,
                                          kCFPreferencesAnyHost)
        }
        return CFPreferencesCopyAppValue(key as CFString, appID(for: domain))
    }

    /// Order matters: the first key holding a value wins, the way the system
    /// prefers a current key over the legacy one it replaced.
    static func effectiveValue(domain: String, keys: [String]) -> Any? {
        for key in keys {
            if let value = effectiveValue(domain: domain, key: key) { return value }
        }
        return nil
    }

    static func storedValue(domain: String, key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString,
                               appID(for: domain),
                               kCFPreferencesCurrentUser,
                               kCFPreferencesAnyHost)
    }

    @discardableResult
    static func write(_ value: PrefValue?, domain: String, key: String) -> Bool {
        let id = appID(for: domain)
        CFPreferencesSetValue(key as CFString,
                              value?.propertyListValue,
                              id,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(id,
                                        kCFPreferencesCurrentUser,
                                        kCFPreferencesAnyHost)
    }

    @discardableResult
    static func write(_ value: PrefValue?, domain: String, keys: [String]) -> Bool {
        let saved = keys.map { write(value, domain: domain, key: $0) }
        return saved.allSatisfy { $0 }
    }

    @discardableResult
    static func writeRaw(_ value: CFPropertyList?, domain: String, key: String) -> Bool {
        let id = appID(for: domain)
        CFPreferencesSetValue(key as CFString,
                              value,
                              id,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(id,
                                        kCFPreferencesCurrentUser,
                                        kCFPreferencesAnyHost)
    }
}
