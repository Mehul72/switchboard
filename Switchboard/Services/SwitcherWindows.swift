import AppKit
import ApplicationServices
import OSLog

/// Resolved at runtime so a private symbol removed by a macOS update cannot
/// prevent launch; callers fall back when it is missing.
func privateSymbol<Function>(_ name: String, as type: Function.Type) -> Function? {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

struct SwitcherWindowTarget {
    let info: SwitcherWindow
    let element: AXUIElement
}

struct SwitcherWindowSnapshot {
    let windows: [SwitcherWindowTarget]
    let focusedID: UInt32?
}

enum SwitcherWindowError: LocalizedError {
    case permission, identityUnavailable, noLongerAvailable, focusFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Switchboard under Accessibility to switch windows."
        case .identityUnavailable: return "This macOS version does not expose window identities to Switchboard."
        case .noLongerAvailable: return "That window is no longer available. Open the switcher again."
        case .focusFailed(let code): return "macOS could not focus that window (code \(code))."
        }
    }
}

protocol SwitcherWindowProviding: AnyObject {
    func snapshot(frontmostPID: pid_t?, sameAppOnly: Bool,
                  completion: @escaping (Result<SwitcherWindowSnapshot, Error>) -> Void)
    func focus(_ target: SwitcherWindowTarget, completion: @escaping (Result<Void, Error>) -> Void)
    func setRemembersWindows(_ enabled: Bool)
}

extension SwitcherWindowProviding {
    func setRemembersWindows(_ enabled: Bool) {}
}

final class SwitcherWindows: SwitcherWindowProviding {
    private let queue = DispatchQueue(label: "com.Mehul72.switchboard.window-switching", qos: .userInitiated)
    private static let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "window-switcher")
    private typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    private typealias RemoteElementFunction = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias WindowSpacesFunction = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let getWindowID = privateSymbol("_AXUIElementGetWindow", as: WindowIDFunction.self)
    private static let createRemoteElement = privateSymbol("_AXUIElementCreateWithRemoteToken", as: RemoteElementFunction.self)
    private static let mainConnection = privateSymbol("CGSMainConnectionID", as: ConnectionFunction.self)
    private static let copyWindowSpaces = privateSymbol("CGSCopySpacesForWindows", as: WindowSpacesFunction.self)
    private static let remoteLookupSeconds: TimeInterval = 0.25
    /// A full-screen transition finished about 0.4 seconds after the Space
    /// changed on macOS 27.
    private static let spaceSettleSeconds: TimeInterval = 0.8
    private static let activationSettleSeconds: TimeInterval = 0.3
    /// A pick in the switcher records the exact window. Right after it, the app
    /// can still report its previous window as focused, so hooks leave it alone.
    private static let pickSettleSeconds: TimeInterval = 2
    private var recency = ApplicationRecency()
    private var remembersWindows = false
    private var lastPick: (pid: pid_t, at: TimeInterval)?
    /// Only touched on `queue`.
    private var hiddenWindows = HiddenWindowMemory<AXUIElement>()
    /// Only touched on `queue`.
    private var windowRecency = WindowRecency()
    private var observers: [NSObjectProtocol] = []

    init() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { recency.activated(pid) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if name == NSWorkspace.didActivateApplicationNotification {
                    self?.recency.activated(app.processIdentifier)
                    // Focus moves to the app's window a moment after activation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationSettleSeconds) { [weak self] in
                        self?.recordFocusedWindow(ofFrontmost: app.processIdentifier)
                    }
                } else {
                    self?.recency.terminated(app.processIdentifier)
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            self?.rememberWindowsOnShowingSpace()
            // Mid-animation, a window entering full screen is listed as a temporary stand-in.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.spaceSettleSeconds) { [weak self] in
                self?.rememberWindowsOnShowingSpace()
                if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    self?.recordFocusedWindow(ofFrontmost: pid)
                }
            }
        })
    }

    func setRemembersWindows(_ enabled: Bool) {
        remembersWindows = enabled
        guard !enabled else { return }
        queue.async { [self] in
            hiddenWindows.removeAll()
            windowRecency = WindowRecency()
        }
    }

    /// Switches made outside the switcher (the Dock, a click, a swipe to
    /// another Space) still count as using the window that ends up focused.
    private func recordFocusedWindow(ofFrontmost pid: pid_t) {
        guard remembersWindows, pid != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        if let lastPick, lastPick.pid == pid,
           ProcessInfo.processInfo.systemUptime - lastPick.at < Self.pickSettleSeconds { return }
        queue.async { [self] in
            guard AXIsProcessTrusted() else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            guard let window = Self.element(app, kAXFocusedWindowAttribute), let id = Self.windowID(window) else { return }
            windowRecency.used(id)
        }
    }

    /// A window is often on the showing Space only while it is in use, such as
    /// just after entering full screen. Listing the Space's windows then makes
    /// each app number them, so they stay reachable from other Spaces later.
    /// Every app is asked because the frontmost app is often stale at this moment.
    private func rememberWindowsOnShowingSpace() {
        guard remembersWindows else { return }
        let pids = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.map(\.processIdentifier)
        queue.async { [self] in
            guard AXIsProcessTrusted() else { return }
            let existing = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] ?? [])
                .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
            hiddenWindows.keep(only: Set(existing))
            for pid in pids {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.15)
                var list: CFTypeRef?
                guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success else { continue }
                for window in list as? [AXUIElement] ?? [] {
                    if let id = Self.windowID(window) { hiddenWindows.remember(window, for: id) }
                }
            }
        }
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func snapshot(frontmostPID: pid_t?, sameAppOnly: Bool,
                  completion: @escaping (Result<SwitcherWindowSnapshot, Error>) -> Void) {
        let applications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && (!sameAppOnly || $0.processIdentifier == frontmostPID)
        }.sorted { $0.processIdentifier == frontmostPID && $1.processIdentifier != frontmostPID }
        let recentPIDs = recency.pids
        queue.async { [self] in
            let result = enumerate(applications, frontmostPID: frontmostPID, sameAppOnly: sameAppOnly,
                                   recentPIDs: recentPIDs)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func enumerate(_ applications: [NSRunningApplication], frontmostPID: pid_t?, sameAppOnly: Bool,
                           recentPIDs: [pid_t]) -> Result<SwitcherWindowSnapshot, Error> {
        guard AXIsProcessTrusted() else { return .failure(SwitcherWindowError.permission) }
        guard Self.getWindowID != nil else { return .failure(SwitcherWindowError.identityUnavailable) }
        let descriptions = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        let frontToBack = descriptions.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        let (elsewhere, existing) = Self.windowsOnHiddenSpaces(onScreen: Set(frontToBack),
                                                               owners: Set(applications.map(\.processIdentifier)))
        hiddenWindows.keep(only: existing)
        windowRecency.keep(only: existing)
        var targets: [UInt32: SwitcherWindowTarget] = [:]
        var focusedID: UInt32?
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        for application in applications {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                Self.logger.notice("Window enumeration reached its time budget; showing the windows already found")
                break
            }
            let pid = application.processIdentifier
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            if pid == frontmostPID, let focused = Self.element(app, kAXFocusedWindowAttribute) {
                focusedID = Self.windowID(focused)
            }
            var list: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list)
            // An app whose only windows are on other Spaces can report no value.
            guard result == .success || result == .noValue else {
                Self.logger.info("Window list unavailable for pid \(pid): \(result.rawValue)")
                continue
            }
            for window in list as? [AXUIElement] ?? [] {
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                if let id = Self.add(window, of: application, to: &targets) { hiddenWindows.remember(window, for: id) }
            }
            let elsewhereIDs = elsewhere[pid, default: []]
            for id in elsewhereIDs.subtracting(targets.keys) {
                guard let known = hiddenWindows.element(for: id) else { continue }
                if Self.add(known, of: application, to: &targets) != id { hiddenWindows.forget(id) }
            }
            var wanted = hiddenWindows.unsearched(elsewhereIDs.subtracting(targets.keys))
            guard !wanted.isEmpty else { continue }
            // Remote lookup only reaches windows some client has already asked the
            // app about. The main window is reachable directly, which covers a
            // full-screen app nobody has queried since it left the current Space.
            if let main = Self.element(app, kAXMainWindowAttribute), let id = Self.add(main, of: application, to: &targets) {
                hiddenWindows.remember(main, for: id)
            }
            wanted.subtract(targets.keys)
            let scan = Self.remoteWindows(of: pid, matching: wanted, until: deadline)
            for (id, window) in scan.found where Self.add(window, of: application, to: &targets) == id {
                hiddenWindows.remember(window, for: id)
            }
            // A scan cut short by its time budget has not ruled anything out.
            if scan.finished { hiddenWindows.markSearched(wanted.subtracting(targets.keys)) }
        }
        // Like the macOS switcher, apps whose windows are all closed stay reachable.
        if !sameAppOnly {
            let appsWithWindows = Set(targets.values.map(\.info.pid))
            for application in applications where !appsWithWindows.contains(application.processIdentifier) {
                let entry = SwitcherWindow.windowlessApp(pid: application.processIdentifier,
                                                         appName: application.localizedName ?? "Application",
                                                         isHidden: application.isHidden)
                targets[entry.id] = SwitcherWindowTarget(info: entry,
                                                         element: AXUIElementCreateApplication(application.processIdentifier))
            }
        }
        // Opening the switcher means leaving this window, so it is the one to come back to.
        if let focusedID { windowRecency.used(focusedID) }
        let ordered = SwitcherWindow.ordered(targets.values.map(\.info), frontmostPID: frontmostPID,
                                             focusedID: focusedID, sameAppOnly: sameAppOnly,
                                             frontToBack: frontToBack, recentPIDs: recentPIDs,
                                             recentWindowIDs: windowRecency.ids)
        return .success(SwitcherWindowSnapshot(windows: ordered.compactMap { targets[$0.id] }, focusedID: focusedID))
    }

    /// Adds a switchable window and returns its ID; nil for anything else.
    @discardableResult
    private static func add(_ window: AXUIElement, of application: NSRunningApplication,
                            to targets: inout [UInt32: SwitcherWindowTarget]) -> UInt32? {
        AXUIElementSetMessagingTimeout(window, 0.15)
        guard let id = windowID(window) else { return nil }
        guard targets[id] == nil else { return id }
        guard value(window, kAXRoleAttribute) as? String == kAXWindowRole else { return nil }
        let subrole = value(window, kAXSubroleAttribute) as? String
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
        let name = application.localizedName ?? "Application"
        let title = (value(window, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = SwitcherWindow(id: id, pid: application.processIdentifier, appName: name,
                                  title: title.flatMap { $0.isEmpty ? nil : $0 } ?? name,
                                  isMinimized: value(window, kAXMinimizedAttribute) as? Bool ?? false,
                                  isHidden: application.isHidden)
        targets[id] = SwitcherWindowTarget(info: info, element: window)
        return id
    }

    /// WindowServer windows that sit on a Space but are not on screen, by
    /// owner, plus every window that still exists. Off-screen helper windows
    /// belong to no Space and are skipped.
    private static func windowsOnHiddenSpaces(onScreen: Set<UInt32>, owners: Set<pid_t>)
        -> (elsewhere: [pid_t: Set<UInt32>], existing: Set<UInt32>) {
        let descriptions = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
        let existing = Set(descriptions.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        guard let mainConnection, let copyWindowSpaces else {
            logger.notice("Space lookup unavailable; listing windows on showing Spaces only")
            return ([:], existing)
        }
        let connection = mainConnection()
        let allSpaces: Int32 = 1 | 2 | 4 // current, other and user Spaces
        var windows: [pid_t: Set<UInt32>] = [:]
        for description in descriptions where (description[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
            guard let id = (description[kCGWindowNumber as String] as? NSNumber)?.uint32Value, !onScreen.contains(id),
                  let pid = (description[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owners.contains(pid),
                  let spaces = copyWindowSpaces(connection, allSpaces, [NSNumber(value: id)] as CFArray)?
                    .takeRetainedValue() as? [NSNumber], !spaces.isEmpty else { continue }
            windows[pid, default: []].insert(id)
        }
        return (windows, existing)
    }

    /// Accessibility lists only windows on Spaces that are showing. Other
    /// windows are reachable by asking the app for its elements by number.
    private static func remoteWindows(of pid: pid_t, matching wanted: Set<UInt32>,
                                      until deadline: TimeInterval) -> (found: [UInt32: AXUIElement], finished: Bool) {
        guard !wanted.isEmpty, let createRemoteElement else { return ([:], true) }
        let stop = min(deadline, ProcessInfo.processInfo.systemUptime + remoteLookupSeconds)
        // Token layout: pid, 4 zero bytes, the "coco" marker, then a 64-bit element ID.
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var remaining = wanted
        var found: [UInt32: AXUIElement] = [:]
        var newestLiveID: UInt64?
        var finished = true
        for elementID: UInt64 in 0..<UInt64.max {
            guard !remaining.isEmpty, !ElementScan.isPastNewestElement(elementID, newestLiveID: newestLiveID) else { break }
            guard ProcessInfo.processInfo.systemUptime < stop else {
                finished = false
                break
            }
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = createRemoteElement(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.15)
            guard let role = value(element, kAXRoleAttribute) as? String else { continue }
            newestLiveID = elementID
            guard role == kAXWindowRole, let id = windowID(element), remaining.remove(id) != nil else { continue }
            found[id] = element
        }
        // Helper windows also sit on Spaces, so some IDs are expected to stay unresolved.
        if !remaining.isEmpty {
            logger.debug("pid \(pid): \(remaining.count) windows on other Spaces not found, scan finished: \(finished)")
        }
        return (found, finished)
    }

    func focus(_ target: SwitcherWindowTarget, completion: @escaping (Result<Void, Error>) -> Void) {
        lastPick = (target.info.pid, ProcessInfo.processInfo.systemUptime)
        guard !target.info.isWindowlessApp else {
            // With no window to raise, switching means activating the app, as the macOS switcher does.
            guard let app = NSRunningApplication(processIdentifier: target.info.pid), !app.isTerminated else {
                completion(.failure(SwitcherWindowError.noLongerAvailable))
                return
            }
            app.unhide()
            completion(app.activate(options: []) ? .success(()) : .failure(SwitcherWindowError.noLongerAvailable))
            return
        }
        queue.async { [self] in
            windowRecency.used(target.info.id)
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { completion(.failure(SwitcherWindowError.permission)) }
                return
            }
            let window = target.element
            // Restoring from the Dock can animate longer than the discovery
            // timeout. A 150ms limit reports failure even when restoration succeeds.
            AXUIElementSetMessagingTimeout(window, 1)
            guard Self.windowID(window) == target.info.id else {
                DispatchQueue.main.async { completion(.failure(SwitcherWindowError.noLongerAvailable)) }
                return
            }
            if Self.value(window, kAXMinimizedAttribute) as? Bool == true {
                let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                guard result == .success else {
                    Self.logger.error("Restoring window \(target.info.id) failed: \(result.rawValue)")
                    DispatchQueue.main.async { completion(.failure(SwitcherWindowError.focusFailed(result.rawValue))) }
                    return
                }
            }
            // Make this the app's main window before activation, otherwise an
            // app with several windows can bring its previous main window back.
            Self.makeMain(window)
            DispatchQueue.main.async {
                guard let app = NSRunningApplication(processIdentifier: target.info.pid), !app.isTerminated else {
                    completion(.failure(SwitcherWindowError.noLongerAvailable))
                    return
                }
                app.unhide()
                guard app.activate(options: []) else {
                    completion(.failure(SwitcherWindowError.noLongerAvailable))
                    return
                }
                self.queue.async {
                    let result = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    // System Settings on macOS 27 lists AXRaise but answers it with
                    // attributeUnsupported, after activation already brought its window
                    // forward. The active app's main window is the focused one.
                    let focused = result == .success || Self.value(window, kAXMainAttribute) as? Bool == true
                    if result != .success {
                        if focused {
                            Self.logger.info("Window raise returned \(result.rawValue) but the window is main")
                        } else {
                            Self.logger.error("Window raise failed: \(result.rawValue)")
                        }
                    }
                    DispatchQueue.main.async {
                        completion(focused ? .success(()) : .failure(SwitcherWindowError.focusFailed(result.rawValue)))
                    }
                }
            }
        }
    }

    private static func makeMain(_ window: AXUIElement) {
        let result = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        if result != .success { logger.info("Window does not accept main status: \(result.rawValue); trying raise") }
    }

    private static func windowID(_ element: AXUIElement) -> UInt32? {
        var id: UInt32 = 0
        guard let getWindowID, getWindowID(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(owner, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
}
