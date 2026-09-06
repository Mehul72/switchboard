import AppKit
import ApplicationServices
import CoreGraphics

/// What an Accessibility-gated feature should do when the trust database or
/// the stored preference has moved. Both input hooks need the same rule, and
/// getting it wrong either forgets a setting the user chose or leaves a
/// system-wide hook running after its permission was taken away.
enum AccessibilityResumeStep: Equatable {
    case start
    case stop
    case leaveAlone

    static func next(preferenceOn: Bool, permitted: Bool, running: Bool) -> AccessibilityResumeStep {
        guard preferenceOn, permitted else { return running ? .stop : .leaveAlone }
        return running ? .leaveAlone : .start
    }
}

/// Turns the red traffic-light button into a normal quit request when it closes
/// an app's last window. Chrome needs one extra path because closing its final
/// tab destroys the window without pressing the traffic-light button.
final class QuitOnCloseController {
    private struct CloseCandidate {
        let pid: pid_t
        let frame: CGRect
        let timestamp: TimeInterval
        /// The window the button belongs to. The watch follows this window,
        /// not the app, so an unrelated window opening or closing later
        /// cannot be mistaken for the result of this click.
        let window: AXUIElement
    }

    private struct ChromeSample {
        var previouslyHadWindows: Bool
        var zeroSamples: Int
    }

    /// Where the close button sits, before the owning app has been vetted.
    private struct CloseButtonHit {
        let pid: pid_t
        let frame: CGRect
        let window: AXUIElement
    }

    private struct ClickRelease {
        let point: CGPoint
        let timestamp: TimeInterval
    }

    /// What we can actually tell about an app's windows this tick.
    private enum WindowEvidence {
        case hasWindows
        case none
        /// Accessibility did not answer in time. Never a reason to quit.
        case unknown
    }

    /// What the red-button click turned out to mean, judged against the window
    /// that was actually clicked rather than against the app as a whole.
    enum CloseOutcome: Equatable {
        /// The clicked window is still listed, so the close is still in flight.
        case stillClosing
        /// It went away and the app has other windows. An ordinary window
        /// close, which is all the user asked for.
        case otherWindowsRemain
        /// It went away and the app has nothing left.
        case appHasNoWindows
        /// Accessibility did not answer. Never a reason to quit.
        case unknown
    }

    enum CloseWatchStep: Equatable {
        case quit
        /// The question is settled. Stop sampling, so a window swap later in
        /// the same watch cannot be read as this click's result.
        case stop
        case keepWatching(emptySamples: Int)
    }

    /// The decision rule on its own, with no Accessibility in it, because this
    /// is where quitting the wrong app gets decided.
    static func nextCloseWatchStep(after outcome: CloseOutcome,
                                   emptySamples: Int) -> CloseWatchStep {
        switch outcome {
        case .otherWindowsRemain:
            return .stop
        case .stillClosing, .unknown:
            return .keepWatching(emptySamples: 0)
        case .appHasNoWindows:
            let empty = emptySamples + 1
            return empty >= emptySamplesBeforeQuit ? .quit : .keepWatching(emptySamples: empty)
        }
    }

    /// Six agreeing samples at 0.5s. Chrome's window list empties for over a
    /// second during a full-screen transition, and quitting then costs every
    /// open tab, so the bar for a destructive action is deliberately high.
    private static let zeroSamplesBeforeQuit = 6
    private static let pollInterval: TimeInterval = 0.5
    /// An app that just launched has not "closed its last window" yet.
    private static let launchGrace: TimeInterval = 8

    /// The red button stands in for Quit only on an app's *last* window.
    /// Closing one of several is an ordinary window close, so after the click
    /// we watch the window actually go away and quit only if the app is left
    /// with nothing open. Six seconds of watching, because the answer is not
    /// due until the samples below have had time to agree.
    private static let closeConfirmationAttempts = 24
    private static let closeConfirmationDelay: TimeInterval = 0.1
    private static let closeConfirmationInterval: TimeInterval = 0.25
    /// Six agreeing samples, a second and a half, because Chrome's window list
    /// empties for over a second during a full-screen transition and quitting
    /// then would cost every open tab.
    static let emptySamplesBeforeQuit = 6
    /// A window the user can currently see counts at any size a person could
    /// click, which is what catches mini-players and small utility windows.
    private static let smallestOnscreenWindowPoints: Double = 24
    /// The Accessibility hit test runs for every click anywhere on the system,
    /// so an app that is not answering must not be able to stall the probe.
    private static let hitTestTimeoutSeconds: Float = 0.15
    private static let windowListTimeoutSeconds: Float = 0.25
    /// Longer than this and the press and release are not one click.
    private static let maximumClickSeconds: TimeInterval = 3
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
    private let windowProbeQueue = DispatchQueue(label: "com.Mehul72.switchboard.window-probe",
                                                 qos: .utility)
    private var mouseMonitor: Any?
    private var chromeTimer: Timer?
    private var closeCandidate: CloseCandidate?
    private var chromeSamples: [pid_t: ChromeSample] = [:]
    private var quittingPIDs: Set<pid_t> = []
    private var chromePollInFlight = false
    private var monitoringGeneration = 0
    /// Identifies the newest press, so a slow probe for a press the user has
    /// already moved on from cannot install a stale candidate.
    private var clickProbeSequence = 0
    private var probeAwaitingAnswer: Int?
    private var releaseAwaitingProbe: ClickRelease?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        resumeIfPermitted()
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

    /// Accessibility is granted in System Settings long after launch, and an
    /// app update can revoke it. Either way the stored preference is what the
    /// user asked for, so it survives and the monitor follows the permission.
    @discardableResult
    func resumeIfPermitted() -> Bool {
        switch AccessibilityResumeStep.next(preferenceOn: defaults.bool(forKey: Self.defaultsKey),
                                            permitted: Self.hasPermission,
                                            running: isActive) {
        case .start: return start()
        case .stop: stop(); return false
        case .leaveAlone: return isActive
        }
    }

    func revalidatePermission() {
        resumeIfPermitted()
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
        probeAwaitingAnswer = nil
        releaseAwaitingProbe = nil
        chromeSamples.removeAll()
        quittingPIDs.removeAll()
        return true
    }

    private func handleMouse(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent else { return }
        let point = cgEvent.location

        switch event.type {
        case .leftMouseDown:
            probeForCloseButton(at: point, timestamp: event.timestamp)
        case .leftMouseUp:
            matchRelease(at: point, timestamp: event.timestamp)
        default:
            break
        }
    }

    /// The hit test walks the Accessibility tree of whatever is under the
    /// cursor and can block for its full messaging timeout against an app that
    /// is not answering. This runs for every click anywhere on the system, so
    /// it stays off the main thread and only the verdict comes back.
    private func probeForCloseButton(at point: CGPoint, timestamp: TimeInterval) {
        closeCandidate = nil
        releaseAwaitingProbe = nil
        clickProbeSequence &+= 1
        let sequence = clickProbeSequence
        let generation = monitoringGeneration
        // Set before dispatching: the release runs on this same thread and
        // must never see the gap between handing off and recording the wait.
        probeAwaitingAnswer = sequence

        windowProbeQueue.async { [weak self] in
            guard let self else { return }
            let hit = Self.closeButtonHit(at: point)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.monitoringGeneration == generation,
                      self.clickProbeSequence == sequence else { return }

                self.probeAwaitingAnswer = nil
                self.closeCandidate = self.managedCandidate(hit, timestamp: timestamp)
                if let release = self.releaseAwaitingProbe {
                    self.releaseAwaitingProbe = nil
                    self.confirmClose(at: release.point, timestamp: release.timestamp)
                }
            }
        }
    }

    private func matchRelease(at point: CGPoint, timestamp: TimeInterval) {
        // The probe is off the main thread, so the release can arrive before
        // its answer does. Whichever lands second does the matching.
        guard probeAwaitingAnswer == nil else {
            releaseAwaitingProbe = ClickRelease(point: point, timestamp: timestamp)
            return
        }
        confirmClose(at: point, timestamp: timestamp)
    }

    private func confirmClose(at point: CGPoint, timestamp: TimeInterval) {
        guard let candidate = closeCandidate else { return }
        closeCandidate = nil
        guard timestamp - candidate.timestamp < Self.maximumClickSeconds,
              candidate.frame.contains(point) else { return }

        let generation = monitoringGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeConfirmationDelay) { [weak self] in
            self?.confirmLastWindowClosed(pid: candidate.pid,
                                          clickedWindow: candidate.window,
                                          attempt: 0,
                                          emptySamples: 0,
                                          generation: generation)
        }
    }

    /// The Accessibility half of the hit test says which process owns the
    /// button; whether Switchboard manages that app is an AppKit question and
    /// is answered here on the main thread.
    private func managedCandidate(_ hit: CloseButtonHit?,
                                  timestamp: TimeInterval) -> CloseCandidate? {
        guard let hit,
              let application = NSRunningApplication(processIdentifier: hit.pid),
              shouldManage(application) else { return nil }
        return CloseCandidate(pid: hit.pid, frame: hit.frame,
                              timestamp: timestamp, window: hit.window)
    }

    /// Waits for the clicked window to disappear, then quits the app only if
    /// nothing is left behind. An app with other windows still open, one whose
    /// close was cancelled by a save sheet, and one that never answered are all
    /// left alone: the window close on its own is what the user asked for.
    private func confirmLastWindowClosed(pid: pid_t,
                                         clickedWindow: AXUIElement,
                                         attempt: Int,
                                         emptySamples: Int,
                                         generation: Int) {
        guard isActive,
              monitoringGeneration == generation,
              attempt < Self.closeConfirmationAttempts else { return }

        windowProbeQueue.async { [weak self] in
            guard let self else { return }
            let outcome = Self.closeOutcome(pid: pid, clickedWindow: clickedWindow)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.monitoringGeneration == generation,
                      self.isActive else { return }

                switch Self.nextCloseWatchStep(after: outcome, emptySamples: emptySamples) {
                case .stop:
                    return
                case .quit:
                    self.requestNormalQuit(pid: pid)
                case .keepWatching(let empty):
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeConfirmationInterval) {
                        self.confirmLastWindowClosed(pid: pid,
                                                     clickedWindow: clickedWindow,
                                                     attempt: attempt + 1,
                                                     emptySamples: empty,
                                                     generation: generation)
                    }
                }
            }
        }
    }

    /// What the two window sources add up to, kept pure because reading them
    /// wrong is how the feature quietly stopped quitting anything.
    ///
    /// Only Accessibility may settle the question against quitting. It is the
    /// authority on what an app still owns: it lists windows across every
    /// Space and keeps listing one after it is minimized.
    ///
    /// Pixels are a much weaker signal and only say "not yet". Accessibility
    /// drops a window from its list before the close animation has finished
    /// drawing, so for the first fraction of a second after a click the app
    /// looks like it has no windows while its old one is still on screen.
    /// Reading that as another window made the very first sample terminal, so
    /// every watch ended in `otherWindowsRemain` and no app was ever quit.
    static func closeOutcome(clickedWindowStillListed: Bool,
                             hasOtherAccessibilityWindows: Bool,
                             anythingVisible: Bool) -> CloseOutcome {
        if clickedWindowStillListed { return .stillClosing }
        if hasOtherAccessibilityWindows { return .otherWindowsRemain }
        return anythingVisible ? .stillClosing : .appHasNoWindows
    }

    /// Judges the click against the window it was made on, so an unrelated
    /// window opening later cannot be mistaken for this click's result.
    private static func closeOutcome(pid: pid_t, clickedWindow: AXUIElement) -> CloseOutcome {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.windowListTimeoutSeconds)
        guard let windows = elements(of: application,
                                     attribute: kAXWindowsAttribute as CFString) else {
            return .unknown
        }
        let stillListed = windows.contains { CFEqual($0, clickedWindow) }
        return closeOutcome(
            clickedWindowStillListed: stillListed,
            hasOtherAccessibilityWindows: !windows.isEmpty && !stillListed,
            anythingVisible: windows.isEmpty && hasVisibleWindow(pid: pid)
        )
    }

    /// Accessibility only, so this is safe to run away from the main thread.
    private static func closeButtonHit(at point: CGPoint) -> CloseButtonHit? {
        var hitElement: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.hitTestTimeoutSeconds)
        guard AXUIElementCopyElementAtPosition(system,
                                               Float(point.x),
                                               Float(point.y),
                                               &hitElement) == .success,
              let hitElement else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hitElement, &pid) == .success else { return nil }

        let axApplication = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApplication, Self.hitTestTimeoutSeconds)
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
            return CloseButtonHit(pid: pid, frame: frame, window: window)
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

        windowProbeQueue.async { [weak self] in
            guard let self else { return }
            var counts: [pid_t: WindowEvidence] = [:]
            for pid in runningPIDs {
                counts[pid] = Self.windowEvidence(pid: pid)
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

    /// Accessibility can briefly empty its window list during Space moves,
    /// full-screen transitions and renderer stalls. CoreGraphics sees every
    /// Space independently, so both sources must agree before we act.
    private static func windowEvidence(pid: pid_t) -> WindowEvidence {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.windowListTimeoutSeconds)
        guard let windows = elements(of: application,
                                     attribute: kAXWindowsAttribute as CFString) else {
            return .unknown
        }
        if !windows.isEmpty { return .hasWindows }
        return Self.hasVisibleWindow(pid: pid) ? .hasWindows : .none
    }

    /// Whether the app has a window the user can actually see right now.
    ///
    /// Accessibility, not this, is the authority on whether an app still has
    /// windows: it lists them across every Space and keeps listing a window
    /// after it is minimized. This is only the safety net for the moment
    /// Accessibility goes briefly blank during a Space or full-screen change,
    /// so it asks the narrower question and lets the window server decide what
    /// counts as visible.
    ///
    /// It deliberately ignores offscreen windows. Every app parks layer-0
    /// windows that outlive the ones it shows, and nothing in the window list
    /// tells them apart from a real window on another Space: with no document
    /// open at all, TextEdit still reports a 500x500 helper and the full
    /// 673x439 ghost of a window closed minutes earlier, both far past any
    /// plausible size cutoff. Counting those made this return true forever,
    /// which ended every watch at `otherWindowsRemain` and left the feature
    /// unable to quit anything.
    private static func hasVisibleWindow(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            return true // no answer is not evidence of absence
        }
        return windows.contains { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double else { return false }
            return width > Self.smallestOnscreenWindowPoints
                && height > Self.smallestOnscreenWindowPoints
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

    private static func value(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func elements(of element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        value(of: element, attribute: attribute) as? [AXUIElement]
    }

    private static func element(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        guard let value = value(of: element, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func bool(of element: AXUIElement, attribute: CFString) -> Bool? {
        value(of: element, attribute: attribute) as? Bool
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
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
