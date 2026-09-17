import Foundation

/// One installed copy of the app. macOS has no uninstall hook and keeps
/// preferences after the app is trashed, so a reinstall can only be recognised
/// by the bundle on disk: a new copy gets a new inode, while relaunching,
/// moving within the volume, or App Translocation keep it.
struct AppCopy: Equatable {
    let id: String
}

extension AppCopy {
    // Inodes are only unique within a volume; the build number keeps copies
    // run from two different disk images apart.
    init(bundleURL: URL, build: String) throws {
        var info = stat()
        guard stat(bundleURL.path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        id = "\(info.st_ino)-\(build)"
    }

    static func current() throws -> AppCopy {
        try AppCopy(bundleURL: Bundle.main.bundleURL,
                    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
    }
}

/// Lets the welcome window open once for each copy of the app.
struct WelcomeGate {
    static let shownCopiesKey = "WelcomeShownCopies"
    // Covers switching between a development build and the installed app
    // without letting the list grow with every update.
    static let rememberedCopyLimit = 20

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True only the first time a copy asks. The copy is recorded before the
    /// welcome is shown, so quitting with it still open does not bring it back.
    func claim(_ copy: AppCopy) -> Bool {
        let shown = defaults.stringArray(forKey: Self.shownCopiesKey) ?? []
        // The copy in use moves to the end, so the limit drops copies that
        // have not launched in a while rather than the one running now.
        let updated = Array((shown.filter { $0 != copy.id } + [copy.id]).suffix(Self.rememberedCopyLimit))
        if updated != shown {
            defaults.set(updated, forKey: Self.shownCopiesKey)
        }
        return !shown.contains(copy.id)
    }
}
