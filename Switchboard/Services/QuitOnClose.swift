import AppKit
import ApplicationServices
import CoreGraphics

/// Turns the red traffic-light button into a normal quit request. Chrome needs
/// one extra path because closing its final tab destroys the window without
/// pressing the traffic-light button.
final class QuitOnCloseController {
    private struct CloseCandidate {
        let pid: pid_t
        let frame: CGRect
        let timestamp: TimeInterval
    }

    private struct ChromeSample {
        var previouslyHadWindows: Bool
        var zeroSamples: Int
    }

    /// What we can actually tell about an app's windows this tick.
    private enum WindowEvidence {
        case hasWindows
        case none
        /// Accessibility did not answer in time. Never a reason to quit.
        case unknown
    }

    /// Six agreeing samples at 0.5s. Chrome's window list empties for over a
    /// second during a full-screen transition, and quitting then costs every
    /// open tab, so the bar for a destructive action is deliberately high.
    private static let zeroSamplesBeforeQuit = 6
    private static let pollInterval: TimeInterval = 0.5
    /// An app that just launched has not "closed its last window" yet.
    private static let launchGrace: TimeInterval = 8

    private static let defaultsKey = "QuitOnCloseEnabled"
    private static let excludedBundleIDs: Set<String> = [
        "com.Mehul72.switchboard",
        "com.apple.finder"
    ]
    private static let chromeBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium"
    ]

    private let defaults: UserDefaults
    private let chromePollQueue = DispatchQueue(label: "com.Mehul72.switchboard.chrome-windows",
                                                qos: .utility)
    private var mouseMonitor: Any?
    private var chromeTimer: Timer?
    private var closeCandidate: CloseCandidate?
    private var chromeSamples: [pid_t: ChromeSample] = [:]
    private var quittingPIDs: Set<pid_t> = []
    private var chromePollInFlight = false
    private var monitoringGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Self.defaultsKey) {
            let resumed = Self.hasPermission && start()
            if !resumed {
                defaults.set(false, forKey: Self.defaultsKey)
            }
        }
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    var isActive: Bool { mouseMonitor != nil }

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        if !active {
            stop()
            defaults.set(false, forKey: Self.defaultsKey)
            return true
        }
        if isActive { return true }
        let started = start()
        defaults.set(started, forKey: Self.defaultsKey)
        return started
    }

    func revalidatePermission() {
        if isActive, !Self.hasPermission {
            _ = setActive(false)
        }
    }

    private func start() -> Bool {
        guard Self.hasPermission else { return false }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            self?.handleMouse(event)
        }
        guard mouseMonitor != nil else { return false }

        monitoringGeneration &+= 1
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.pollChromeWindows()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        chromeTimer = timer
        pollChromeWindows()
        return true
    }

    @discardableResult
    private func stop() -> Bool {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        chromeTimer?.invalidate()
        chromeTimer = nil
        monitoringGeneration &+= 1
        chromePollInFlight = false
        closeCandidate = nil
        chromeSamples.removeAll()
        quittingPIDs.removeAll()
        return true
    }

    private func handleMouse(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent else { return }
        let point = cgEvent.location

        switch event.type {
        case .leftMouseDown:
            closeCandidate = candidate(at: point, timestamp: event.timestamp)
        case .leftMouseUp:
            guard let candidate = closeCandidate else { return }
            closeCandidate = nil
            guard event.timestamp - candidate.timestamp < 3,
                  candidate.frame.contains(point) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.requestNormalQuit(pid: candidate.pid)
            }
        default:
            break
        }
    }

    private func candidate(at point: CGPoint,
                           timestamp: TimeInterval) -> CloseCandidate? {
        var hitElement: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        // This runs on the main thread for every click anywhere on the system,
        // so an unresponsive app must not be able to stall the cursor.
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard AXUIElementCopyElementAtPosition(system,
                                               Float(point.x),
                                               Float(point.y),
                                               &hitElement) == .success,
              let hitElement else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hitElement, &pid) == .success,
              let application = NSRunningApplication(processIdentifier: pid),
              shouldManage(application) else { return nil }

        let axApplication = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApplication, 0.15)
        let windows: [AXUIElement]
        if let hitWindow = element(of: hitElement,
                                   attribute: kAXWindowAttribute as CFString) {
            windows = [hitWindow]
        } else {
            guard let applicationWindows = elements(
                of: axApplication,
                attribute: kAXWindowsAttribute as CFString
            ) else { return nil }
            windows = applicationWindows
        }

        for window in windows {
            guard let closeButton = element(of: window,
                                            attribute: kAXCloseButtonAttribute as CFString),
                  CFEqual(hitElement, closeButton),
                  bool(of: closeButton,
                       attribute: kAXEnabledAttribute as CFString) == true,
                  let frame = frame(of: closeButton),
                  frame.contains(point) else { continue }
            return CloseCandidate(pid: pid, frame: frame, timestamp: timestamp)
        }
        return nil
    }

    private func pollChromeWindows() {
        guard Self.hasPermission else {
            _ = setActive(false)
            return
        }
        guard !chromePollInFlight else { return }

        let applications = chromeApplications()
        let runningPIDs = Set(applications.map(\.processIdentifier))
        let generation = monitoringGeneration
        chromePollInFlight = true

        chromePollQueue.async { [weak self] in
            guard let self else { return }
            var counts: [pid_t: WindowEvidence] = [:]
            for pid in runningPIDs {
                counts[pid] = self.windowEvidence(pid: pid)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.monitoringGeneration == generation,
                      self.isActive else { return }
                self.chromePollInFlight = false
                self.applyChromeWindowCounts(counts, runningPIDs: runningPIDs)
            }
        }
    }

    private func applyChromeWindowCounts(_ counts: [pid_t: WindowEvidence],
                                         runningPIDs: Set<pid_t>) {
        chromeSamples = chromeSamples.filter { runningPIDs.contains($0.key) }

        for (pid, evidence) in counts {
            var sample = chromeSamples[pid]
                ?? ChromeSample(previouslyHadWindows: evidence == .hasWindows, zeroSamples: 0)

            switch evidence {
            case .hasWindows:
                sample.previouslyHadWindows = true
                sample.zeroSamples = 0
            case .unknown:
                // Accessibility went quiet. That tells us nothing, so hold the
                // count rather than drifting towards a quit.
                sample.zeroSamples = 0
            case .none:
                guard sample.previouslyHadWindows, !justLaunched(pid: pid) else { break }
                sample.zeroSamples += 1
                if sample.zeroSamples >= Self.zeroSamplesBeforeQuit {
                    sample.previouslyHadWindows = false
                    sample.zeroSamples = 0
                    requestNormalQuit(pid: pid)
                }
            }
            chromeSamples[pid] = sample
        }
    }

    private func justLaunched(pid: pid_t) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: pid),
              let launched = application.launchDate else { return false }
        return Date().timeIntervalSince(launched) < Self.launchGrace
    }

    private func chromeApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { application in
            guard let bundleID = application.bundleIdentifier else { return false }
            return Self.chromeBundleIDs.contains(bundleID)
                && shouldManage(application)
        }
    }

    /// Accessibility alone is not trustworthy enough to quit on: Chrome empties
    /// its AX window list during full-screen transitions, Space moves and
    /// renderer stalls. CoreGraphics' window list is independent of whether the
    /// app is answering Accessibility, so both have to agree before we act.
    private func windowEvidence(pid: pid_t) -> WindowEvidence {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let windows = elements(of: application,
                                     attribute: kAXWindowsAttribute as CFString) else {
            return .unknown
        }
        if !windows.isEmpty { return .hasWindows }
        return Self.hasCoreGraphicsWindows(pid: pid) ? .hasWindows : .none
    }

    /// Counts real windows only: layer 0 excludes menus, tooltips and panels,
    /// and `optionAll` keeps minimised windows in view. Window titles need
    /// Screen Recording, but owner, layer and size do not.
    private static func hasCoreGraphicsWindows(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return true // no answer is not evidence of absence
        }
        return windows.contains { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else { return false }
            return width > 80 && height > 80
        }
    }

    private func requestNormalQuit(pid: pid_t) {
        guard !quittingPIDs.contains(pid),
              let application = NSRunningApplication(processIdentifier: pid),
              shouldManage(application) else { return }

        quittingPIDs.insert(pid)
        if !application.terminate() {
            quittingPIDs.remove(pid)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.quittingPIDs.remove(pid)
        }
    }

    private func shouldManage(_ application: NSRunningApplication) -> Bool {
        guard application.activationPolicy == .regular,
              !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = application.bundleIdentifier,
              !Self.excludedBundleIDs.contains(bundleID) else { return false }
        return true
    }

    private func value(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private func elements(of element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        value(of: element, attribute: attribute) as? [AXUIElement]
    }

    private func element(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        guard let value = value(of: element, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func bool(of element: AXUIElement, attribute: CFString) -> Bool? {
        value(of: element, attribute: attribute) as? Bool
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(of: element,
                                        attribute: kAXPositionAttribute as CFString),
              let sizeValue = value(of: element,
                                    attribute: kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    deinit { stop() }
}
