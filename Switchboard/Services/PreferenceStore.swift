import Foundation

// CFPreferences addresses the global domain by a sentinel app ID rather than
// the "NSGlobalDomain" name that `defaults` accepts.
private func appID(for domain: String) -> CFString {
    domain == "NSGlobalDomain" ? kCFPreferencesAnyApplication : domain as CFString
}

enum PreferenceStore {
    /// What the system would actually use: the domain's own value, falling back
    /// to the global domain and any managed defaults.
    static func effectiveValue(domain: String, key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, appID(for: domain))
    }

    /// Only what is explicitly written into this domain. Used to record whether
    /// a key was unset before we ever touched it.
    static func storedValue(domain: String, key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString,
                               appID(for: domain),
                               kCFPreferencesCurrentUser,
                               kCFPreferencesAnyHost)
    }

    static func write(_ value: PrefValue?, domain: String, key: String) {
        let id = appID(for: domain)
        CFPreferencesSetValue(key as CFString,
                              value?.propertyListValue,
                              id,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(id)
    }

    static func writeRaw(_ value: CFPropertyList?, domain: String, key: String) {
        let id = appID(for: domain)
        CFPreferencesSetValue(key as CFString,
                              value,
                              id,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(id)
    }
}
