import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        // Throws when the app is not in a registerable location -- running from
        // DerivedData, mostly. Nothing useful to do about it here.
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}
