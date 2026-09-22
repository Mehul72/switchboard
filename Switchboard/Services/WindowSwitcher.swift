import AppKit
import Carbon
import Combine
import OSLog

@MainActor
final class WindowSwitcher: ObservableObject {
    @Published private(set) var windows: [SwitcherWindow] = []
    @Published private(set) var images: [UInt32: NSImage] = [:]
    @Published private(set) var selectedID: UInt32?
    @Published private(set) var isLoading = false
    @Published private(set) var hasPreviewsPermission = false
    private(set) var sameAppOnly = false
    var onError: ((String) -> Void)?
    var onBegin: (() -> Void)?
    var isRegisteredShortcut: ((GlobalShortcut) -> Bool)?

    private let inventory: SwitcherWindowProviding
    private let previews: SwitcherPreviews
    private let input: SwitcherInputMonitoring
    private let hasAccessibility: () -> Bool
    private let canCapture: () -> Bool
    private let requestQuit: (pid_t) -> Bool
    private let pointerLocation: () -> CGPoint
    private var quittingPIDs: Set<pid_t> = []
    private var lastHoverPointer: CGPoint?
    private var panel: WindowSwitcherPanel?
    private var session: WindowSwitchingSession?
    private var targets: [SwitcherWindowTarget] = []
    private var generation = UUID()
    private var deadline: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "window-switcher")

    var isShowing: Bool { session != nil }

    init(inventory: SwitcherWindowProviding = SwitcherWindows(), input: SwitcherInputMonitoring? = nil,
         hasAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() },
         canCapture: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         requestQuit: @escaping (pid_t) -> Bool = WindowSwitcher.requestQuit,
         pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
         previews: SwitcherPreviews? = nil) {
        self.inventory = inventory
        self.previews = previews ?? SwitcherPreviews()
        self.input = input ?? SwitcherInput()
        self.hasAccessibility = hasAccessibility
        self.canCapture = canCapture
        self.requestQuit = requestQuit
        self.pointerLocation = pointerLocation
        self.input.onCommand = { [weak self] command in self?.handle(command) }
        self.input.shouldPassShortcut = { [weak self] shortcut in self?.isRegisteredShortcut?(shortcut) ?? false }
        self.previews.onPreview = { [weak self] id, image in
            guard let self, self.windows.contains(where: { $0.id == id }) else { return }
            self.images[id] = image
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            // Window thumbnails do not outlive sleep or another user taking over the screen.
            let forgetsPreviews = name != NSWorkspace.activeSpaceDidChangeNotification
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancel()
                    if forgetsPreviews { self?.discardPreviews() }
                }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.applicationTerminated(app.processIdentifier) }
        })
    }

    func advance(sameAppOnly: Bool, backwards: Bool, modifiers: UInt32) {
        if session != nil {
            guard session?.shouldCommit == false else { return }
            session?.move(by: backwards ? -1 : 1)
            publishSelection()
            return
        }
        guard hasAccessibility() else {
            onError?(SwitcherWindowError.permission.localizedDescription)
            return
        }
        let held = Self.heldFlags(modifiers)
        guard !held.isEmpty, input.start(modifiers: held) else {
            onError?("macOS could not watch switcher keys. Check Switchboard's Accessibility access and try again.")
            return
        }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        self.sameAppOnly = sameAppOnly
        session = WindowSwitchingSession(backwards: backwards)
        lastHoverPointer = pointerLocation()
        isLoading = true
        hasPreviewsPermission = canCapture()
        if !hasPreviewsPermission { previews.discardAll() }
        let token = UUID()
        generation = token
        onBegin?()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        panel = WindowSwitcherPanel(model: self, screen: screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.generation == token, self.session?.shouldCommit == false else { return }
            self.panel?.orderFrontRegardless()
        }
        // A hung Accessibility server must not leave the keyboard captured.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token, self.isLoading else { return }
            self.fail("The window list took too long to load. Try again after the busy app responds.")
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        inventory.snapshot(frontmostPID: frontmostPID, sameAppOnly: sameAppOnly) { [weak self] result in
            guard let self, self.generation == token, self.session != nil else { return }
            self.deadline?.cancel()
            self.deadline = nil
            switch result {
            case .failure(let error): self.fail(error.localizedDescription)
            case .success(let snapshot): self.loaded(snapshot)
            }
        }
        if !input.modifiersAreHeld { commit() }
    }

    private func loaded(_ snapshot: SwitcherWindowSnapshot) {
        targets = snapshot.windows
        windows = targets.map(\.info)
        isLoading = false
        session?.load(windows.map(\.id), focusedID: snapshot.focusedID)
        guard !windows.isEmpty else {
            fail(sameAppOnly ? "This app has no switchable windows." : "No switchable windows are available.")
            return
        }
        publishSelection()
        if session?.shouldCommit == true || !input.modifiersAreHeld {
            commit()
            return
        }
        // Before fit: laying out the panel creates the cards, and their requests
        // would otherwise start ahead of the selected card's.
        if hasPreviewsPermission {
            previews.prune(keeping: Set(windows.map(\.id)))
            images = previews.thumbnails(for: windows.map(\.id))
            if let selectedID { previewNeeded(selectedID) }
        }
        let appCount = windows.filter(\.isWindowlessApp).count
        panel?.fit(windowCount: windows.count - appCount, appCount: appCount)
    }

    /// Cards ask as the grid creates them, so off-screen rows are captured only if scrolled to.
    func previewNeeded(_ id: UInt32) {
        guard session?.shouldCommit == false, hasPreviewsPermission,
              windows.contains(where: { $0.id == id && !$0.isWindowlessApp }) else { return }
        previews.request(id, first: id == selectedID)
    }

    func discardPreviews() {
        previews.discardAll()
        images = [:]
    }

    /// While on, the inventory notes windows as Spaces change so full-screen
    /// windows stay reachable. Off closes the switcher and forgets what it kept.
    func setEnabled(_ enabled: Bool) {
        inventory.setRemembersWindows(enabled)
        guard !enabled else { return }
        cancel()
        discardPreviews()
    }

    func choose(_ id: UInt32) {
        session?.select(id)
        publishSelection()
        commit()
    }

    /// A panel opening or scrolling under a still pointer reports hover too.
    /// Only movement is a choice, otherwise the keyboard selection would jump.
    func hover(_ id: UInt32) {
        let pointer = pointerLocation()
        guard session != nil, pointer != lastHoverPointer else { return }
        lastHoverPointer = pointer
        let previous = session?.selectedID
        session?.select(id)
        // Hover reports every move inside a card; announce only a new selection.
        guard session?.selectedID != previous else { return }
        publishSelection()
    }

    private func quitSelectedApp() {
        guard session?.shouldCommit == false, let selected = windows.first(where: { $0.id == selectedID }),
              !quittingPIDs.contains(selected.pid) else { return }
        guard requestQuit(selected.pid) else {
            NSSound.beep()
            return
        }
        quittingPIDs.insert(selected.pid)
    }

    func applicationTerminated(_ pid: pid_t) {
        let gone = Set(windows.filter { $0.pid == pid }.map(\.id))
        guard session != nil, !gone.isEmpty else { return }
        session?.remove(gone)
        targets.removeAll { gone.contains($0.info.id) }
        windows = targets.map(\.info)
        for id in gone { images[id] = nil }
        guard !windows.isEmpty else {
            cancel()
            return
        }
        let appCount = windows.filter(\.isWindowlessApp).count
        panel?.fit(windowCount: windows.count - appCount, appCount: appCount)
        publishSelection()
    }

    /// The Dock's quit request, which lets the app ask about unsaved work.
    /// Finder stays running, as with quit-on-close.
    nonisolated static func requestQuit(_ pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier != "com.apple.finder" else { return false }
        return app.terminate()
    }

    func commit() {
        guard session != nil else { return }
        session?.release()
        input.stop()
        panel?.orderOut(nil)
        guard !isLoading else { return }
        let target = targets.first { $0.info.id == session?.selectedID }
        let quitting = quittingPIDs
        cancel()
        // Focusing an app mid-quit races its exit and reports a vanished window as an error.
        guard let target, !quitting.contains(target.info.pid) else { return }
        let token = generation
        inventory.focus(target) { [weak self] result in
            guard let self, self.generation == token else { return }
            if case .failure(let error) = result { self.fail(error.localizedDescription) }
        }
    }

    func cancel() {
        generation = UUID()
        deadline?.cancel()
        deadline = nil
        session = nil
        input.stop()
        previews.cancelRequests()
        panel?.orderOut(nil)
        panel = nil
        targets = []
        windows = []
        images = [:]
        selectedID = nil
        isLoading = false
        quittingPIDs = []
    }

    func requestPreviews() {
        cancel()
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func handle(_ command: SwitcherInput.Command) {
        switch command {
        case .move(let offset):
            session?.move(by: offset)
            publishSelection()
        case .commit: commit()
        case .cancel: cancel()
        case .quit: quitSelectedApp()
        case .click(let point):
            let height = NSScreen.screens.first?.frame.height ?? 0
            let appKitPoint = CGPoint(x: point.x, y: height - point.y)
            if panel?.frame.contains(appKitPoint) != true { cancel() }
        }
    }

    private func publishSelection() {
        selectedID = session?.selectedID
        guard let selected = windows.first(where: { $0.id == selectedID }), let panel else { return }
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: "\(selected.appName), \(selected.title)",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func fail(_ message: String) {
        cancel()
        logger.error("\(message, privacy: .public)")
        onError?(message)
    }

    static func heldFlags(_ modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        // Shift changes direction and must not finish a reverse invocation.
        return flags
    }

    deinit {
        deadline?.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
