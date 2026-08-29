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
