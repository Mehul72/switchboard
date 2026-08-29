import ServiceManagement

enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    static var isEnabled: Bool {
        state == .enabled
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Result<State, Error> {
        do {
            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            return .success(state)
        } catch {
            return .failure(error)
        }
    }
}
