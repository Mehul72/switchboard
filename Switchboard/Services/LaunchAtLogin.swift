import AppKit
import ServiceManagement

enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable
    }

    enum RecoveryResult {
        case relaunched
        case needsInstallation
        case failed
    }

    static var isEnabled: Bool {
        state == .enabled
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        // ServiceManagement cannot resolve a build that has been deleted
        // underneath a running process, or a copy launched from a disk image.
        // An installed app is still worth letting the user register again.
        case .notFound: return isCurrentApplicationInstalled ? .disabled : .unavailable
        @unknown default: return .unavailable
        }
    }

    static var recoveryTitle: String {
        installedApplicationURL == nil
            ? "Move Switchboard to Applications…"
            : "Restart Switchboard from Applications…"
    }

    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func recoverFromUnavailableCopy(completion: @escaping (RecoveryResult) -> Void) {
        guard let installedApplicationURL else {
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            completion(.needsInstallation)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        // The unusable copy has the same bundle identifier, so Launch Services
        // otherwise hands back the process that is already running.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installedApplicationURL,
                                           configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    completion(.relaunched)
                    NSApp.terminate(nil)
                } else {
                    completion(.failed)
                }
            }
        }
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

    private static var isCurrentApplicationInstalled: Bool {
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: currentURL.path) else { return false }

        return applicationDirectories.contains { directory in
            currentURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
        }
    }

    private static var installedApplicationURL: URL? {
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        let bundleName = Bundle.main.bundleURL.lastPathComponent
        guard let expectedIdentifier = Bundle.main.bundleIdentifier else { return nil }
        var candidates = applicationDirectories.map {
            $0.appendingPathComponent(bundleName, isDirectory: true)
        }

        if let registeredURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: expectedIdentifier
        ) {
            candidates.append(registeredURL)
        }

        return candidates.first { candidate in
            let candidateURL = candidate.standardizedFileURL
            guard candidateURL != currentURL,
                  FileManager.default.fileExists(atPath: candidateURL.path),
                  let candidateBundle = Bundle(url: candidateURL) else { return false }
            return candidateBundle.bundleIdentifier == expectedIdentifier
        }
    }

    private static var applicationDirectories: [URL] {
        FileManager.default.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
    }
}
