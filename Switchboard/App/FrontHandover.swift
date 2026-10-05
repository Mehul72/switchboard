import AppKit
import OSLog

/// Gives the front back to a full-screen app before the panel opens over it.
///
/// A panel opening from the menu bar makes macOS bring the menu bar in, and
/// over a full-screen Space that makes the Space's own app the front one. If
/// Switchboard is the front app at that moment, as it is after any click in
/// its panel, it loses the front about 40 ms after the panel opens, and the
/// panel closes when another app takes the front: it flashed and was gone.
/// With the front handed back first, the panel opens the way it does from a
/// menu bar click, over the other app, and stays.
@MainActor
final class FrontHandover {
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "menu-panel")
    private let workspaceNotifications: NotificationCenter
    private let appNotifications: NotificationCenter
    private let waitLimitSeconds: TimeInterval

    /// Whether macOS counts Switchboard as the front app.
    var isFrontApp: () -> Bool = { NSRunningApplication.current.isActive }
    /// Whether AppKit still counts the app as active. It and the workspace
    /// hear of a change a millisecond or two apart.
    var isActiveInAppKit: () -> Bool = { NSApp.isActive }
    /// The app whose full-screen Space the screen is showing. Nil on a desktop.
    var fullScreenApp: (NSScreen?) -> NSRunningApplication? = { FrontHandover.appOwningFullScreenSpace(on: $0) }
    /// Asks macOS to make the app the front one. False when macOS refuses.
    var giveFront: (NSRunningApplication) -> Bool = { FrontHandover.giveFront(to: $0) }

    private var present: (() -> Void)?
    private var otherAppIsFront = false
    private var appKitHasResigned = false
    private var activationObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var waitLimit: DispatchWorkItem?

    /// The wait limit only matters if macOS never reports the change. Measured,
    /// both reports are in within a few milliseconds.
    init(workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         appNotifications: NotificationCenter = .default,
         waitLimitSeconds: TimeInterval = 0.3) {
        self.workspaceNotifications = workspaceNotifications
        self.appNotifications = appNotifications
        self.waitLimitSeconds = waitLimitSeconds
    }

    /// Runs `present` once Switchboard is not the front app over a full-screen
    /// Space: at once in every other case, a few milliseconds later in that one.
    func handBack(on screen: NSScreen?, then present: @escaping () -> Void) {
        guard self.present == nil else {
            // Already handing back. The newest request is the one to honour.
            self.present = present
            return
        }
        guard isFrontApp(), let app = fullScreenApp(screen) else {
            present()
            return
        }
        guard giveFront(app) else {
            logger.notice("macOS would not hand the front to \(app.bundleIdentifier ?? "the full-screen app", privacy: .public); opening the panel anyway")
            present()
            return
        }
        self.present = present
        waitUntilNotFront()
    }

    /// The panel closes itself when the workspace reports another app in
    /// front, and AppKit closes a popover holding the keyboard when its app
    /// resigns, so neither report may still be on its way when the panel opens.
    private func waitUntilNotFront() {
        otherAppIsFront = false
        appKitHasResigned = !isActiveInAppKit()
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        activationObserver = workspaceNotifications.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                                object: nil, queue: .main) { [weak self] notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let activated, activated.processIdentifier != ownProcess else { return }
            MainActor.assumeIsolated {
                self?.otherAppIsFront = true
                self?.presentIfSettled()
            }
        }
        resignObserver = appNotifications.addObserver(forName: NSApplication.didResignActiveNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.appKitHasResigned = true
                self?.presentIfSettled()
            }
        }
        let limit = DispatchWorkItem { [weak self] in
            self?.logger.notice("The front was not handed back in time; opening the panel anyway")
            self?.finish()
        }
        waitLimit = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + waitLimitSeconds, execute: limit)
    }

    private func presentIfSettled() {
        guard otherAppIsFront, appKitHasResigned else { return }
        finish()
    }

    private func finish() {
        stopWaiting()
        let present = self.present
        self.present = nil
        present?()
    }

    private func stopWaiting() {
        if let activationObserver { workspaceNotifications.removeObserver(activationObserver) }
        if let resignObserver { appNotifications.removeObserver(resignObserver) }
        activationObserver = nil
        resignObserver = nil
        waitLimit?.cancel()
        waitLimit = nil
    }

    /// The menu bar still belongs to the full-screen app while Switchboard is
    /// in front, and in Split View it names the half that was last in use.
    private static func appOwningFullScreenSpace(on screen: NSScreen?) -> NSRunningApplication? {
        guard WindowServerSpaces.isShowingFullScreenSpace(on: screen),
              let owner = NSWorkspace.shared.menuBarOwningApplication,
              owner.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return owner
    }

    private static func giveFront(to app: NSRunningApplication) -> Bool {
        NSApp.yieldActivation(to: app)
        return app.activate(from: .current, options: [])
    }

    deinit {
        if let activationObserver { workspaceNotifications.removeObserver(activationObserver) }
        if let resignObserver { appNotifications.removeObserver(resignObserver) }
        waitLimit?.cancel()
    }
}
