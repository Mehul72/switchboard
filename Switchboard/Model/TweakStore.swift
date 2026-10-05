import AppKit
import Foundation
import SwiftUI

struct StoreNotice: Identifiable, Equatable {
    enum Kind { case success, information, error }
    let id = UUID()
    let kind: Kind
    let message: String
    var link: NoticeLink?
}

struct NoticeLink: Equatable {
    let title: String
    let url: URL

    // macOS shows its own permission prompt once. After that, these are the
    // only way to the right pane without hunting through System Settings.
    static let accessibilitySettings = NoticeLink(
        title: "Open Accessibility Settings",
        url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    static let screenRecordingSettings = NoticeLink(
        title: "Open Screen Recording Settings",
        url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
}

/// Things Switchboard does without being asked each time. All are on until
/// someone switches one off in the settings gear.
enum OptionalBehavior: String, CaseIterable, Identifiable {
    case clipboardHistory = "ClipboardHistoryEnabled"
    case shelfDragTrigger = "ShelfOpensDuringDrags"
    case finderEject = "FinderCommandDeleteEjects"

    var id: Self { self }
    var defaultsKey: String { rawValue }

    var menuTitle: String {
        switch self {
        case .clipboardHistory: return "Record Clipboard History"
        case .shelfDragTrigger: return "Open Shelf During File Drags"
        case .finderEject: return "Command-Delete Ejects Disks in Finder"
        }
    }

    func confirmation(enabled: Bool) -> String {
        switch (self, enabled) {
        case (.clipboardHistory, true): return "Clipboard history is recording again."
        case (.clipboardHistory, false): return "Clipboard history is off, and its clips are forgotten."
        case (.shelfDragTrigger, true): return "Shake the pointer or press Shift during a file drag to open the shelf."
        case (.shelfDragTrigger, false): return "The shelf no longer opens during drags. Its shortcut and tray button still work."
        case (.finderEject, true): return "Command-Delete ejects disks selected in Finder."
        case (.finderEject, false): return "Command-Delete in Finder is left to Finder."
        }
    }
}

@MainActor
final class TweakStore: ObservableObject {
    let catalog: [Tweak]

    @Published var search = ""
    @Published var category: Category = .everyday
    @Published private(set) var pendingRestarts: Set<RestartTarget> = []
    @Published private(set) var values: [String: Any] = [:]
    @Published private(set) var customStates: [String: Bool] = [:]
    /// Drives the live "Ends in" line on the keep-awake row. Nil when off.
    @Published private(set) var keepAwakeSpan: AwakeSpan?
    @Published private(set) var keepAwakeMode: AwakeMode = .off
    @Published private(set) var keepAwakeAllowsDisplaySleep = false
    @Published var notice: StoreNotice?
    @Published private(set) var audioApps: [AudioApp] = []
    @Published private(set) var clips: [ClipEntry] = []

    /// Text waiting on the Translation framework, which only hands out a
    /// session from inside a SwiftUI view, so the popover drives it.
    @Published private(set) var pendingTranslation: PendingTranslation?

    /// The region picker covers the whole screen, so the panel has to get out
    /// of the way while a selection is in progress and come back afterwards.
    var onScreenSelectionBegan: (() -> Void)?
    var onScreenSelectionEnded: (() -> Void)?
    @Published private(set) var audioVolumes: [String: Float] = [:]
    /// Every device an app can be sent to, refreshed alongside the app list so
    /// unplugging one takes it out of the menus.
    @Published private(set) var audioOutputDevices: [AudioOutputDevice] = []
    @Published private(set) var outputDeviceVolumes: [String: OutputVolumeState] = [:]
    /// The device chosen per app, absent when the app follows the system default.
    @Published private(set) var audioRoutes: [String: String] = [:]
    @Published private(set) var systemDefaultOutputUID: String?
    /// The crosshair is up. The panel and the shortcuts stay out of its way.
    @Published private(set) var isSelectingScreenRegion = false
    /// The picture is taken and its text is being read in the background.
    /// Nothing waits for this: a read can take half a minute.
    @Published private(set) var isReadingScreenText = false
    /// True while window shortcuts should be registered: switched on and
    /// allowed under Accessibility.
    @Published private(set) var isWindowSnappingActive = false
    var onWindowSnappingChange: ((Bool) -> Void)?
    @Published private(set) var isWindowSwitchingActive = false
    var onWindowSwitchingChange: ((Bool) -> Void)?
    @Published private(set) var disabledBehaviors: Set<OptionalBehavior> = []
    /// The shelf's drag watcher and the Finder key monitor live with the
    /// menu bar controller, which starts and stops them from here.
    var onBehaviorChange: ((OptionalBehavior, Bool) -> Void)?
    /// Apps the red button never quits, by bundle identifier.
    @Published private(set) var quitOnCloseExclusions: Set<String> = []

    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let ledger: UndoLedger
    private let awake = AwakeController()
    private let scroll: ScrollInverter
    private let quitOnClose: QuitOnCloseController
    private let clipboardImages: ClipboardImageConverter
    private let appAudio: AppAudioEngine
    private let outputVolume = OutputDeviceVolume()
    private let history: ClipboardHistory
    private let screenText: ScreenTextSource
    private static let translateKey = "TranslateCapturedText"
    private static let awakeDisplaySleepKey = "KeepAwakeAllowsDisplaySleep"
    private static let windowSnappingKey = "WindowSnappingEnabled"
    private static let windowSwitchingKey = "WindowSwitchingEnabled"
    private static let recognitionPreparedKey = "TextRecognitionPreparedForSystem"
    /// Master switch for the capture translation feature. While false the
    /// toggle is absent from the catalog and captures are never translated,
    /// even if the preference was switched on earlier.
    nonisolated static let translationEnabled = false
    private var audioMaintenanceTimer: Timer?
    private var isShowingAudioList = false
    private var accessibilityObserver: NSObjectProtocol?
    private var appLaunchObserver: NSObjectProtocol?

    /// The parameters exist so tests can point the store at throwaway
    /// preference domains, a private pasteboard and a stand-in for the screen.
    init(catalog: [Tweak] = TweakCatalog.all,
         defaults: UserDefaults = .standard,
         pasteboard: NSPasteboard = .general,
         screenText: ScreenTextSource = .live) {
        self.catalog = catalog
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.screenText = screenText
        ledger = UndoLedger(defaults: defaults)
        scroll = ScrollInverter(defaults: defaults)
        quitOnClose = QuitOnCloseController(defaults: defaults)
        clipboardImages = ClipboardImageConverter(pasteboard: pasteboard)
        appAudio = AppAudioEngine(defaults: defaults)
        history = ClipboardHistory(pasteboard: pasteboard)
        start()
    }

    private func start() {
        // This retired preference controlled window restoration, not quitting
        // from the red close button. Put it back exactly as it was before the
        // old Switchboard row touched it.
        _ = ledger.restore(domain: "NSGlobalDomain", key: "NSQuitAlwaysKeepsWindows")
        // Granting Accessibility does not restart the app, so without this the
        // toggles keep reporting "not allowed" until something else triggers a
        // refresh. macOS posts this the moment the trust database changes.
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The trust flag lags the notification by a beat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.refresh()
            }
        }
        // An output saved for an app that is not running needs no polling.
        // Its launch is the moment to start watching for it to play.
        appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeAudioPollingForSavedRoutes() }
        }
        history.onChange = { [weak self] in
            guard let self else { return }
            self.clips = self.history.entries
        }
        disabledBehaviors = Set(OptionalBehavior.allCases.filter {
            defaults.object(forKey: $0.defaultsKey) as? Bool == false
        })
        history.setRecording(isEnabled(.clipboardHistory))
        quitOnCloseExclusions = quitOnClose.userExcludedBundleIDs
        keepAwakeAllowsDisplaySleep = defaults.bool(forKey: Self.awakeDisplaySleepKey)
        awake.allowsDisplaySleep = keepAwakeAllowsDisplaySleep
        awake.onHoldChange = { [weak self] in self?.syncKeepAwake() }
        awake.onFinish = { [weak self] reason in
            guard let self else { return }
            self.syncKeepAwake()
            switch reason {
            case .timeUp:
                self.notice = StoreNotice(kind: .information,
                                          message: "Keep awake finished. Normal sleep settings are back.")
            case .appQuit(let name):
                self.notice = StoreNotice(kind: .information,
                                          message: "\(name) quit, so keep awake finished. Normal sleep settings are back.")
            }
        }
        clipboardImages.onReplacement = { [weak self] original in
            self?.history.forgetImage(original)
        }
        prepareTextRecognitionOncePerSystemBuild()
        clipboardImages.onConversion = { [weak self] result in
            switch result {
            case .success(let format):
                self?.notice = StoreNotice(kind: .success,
                                           message: "Clipboard image converted to \(format.label).")
            case .failure(let error):
                self?.notice = StoreNotice(kind: .error,
                                           message: error.localizedDescription)
            }
        }
        refresh()
    }

    func refresh() {
        var latest: [String: Any] = [:]
        for tweak in catalog {
            guard let preference = tweak.preference else { continue }
            if let value = PreferenceStore.effectiveValue(domain: preference.domain, keys: preference.keys) {
                latest[tweak.id] = value
            }
        }
        values = latest
        // Both input hooks are gated on Accessibility, which is granted and
        // revoked outside the app, so every refresh reconciles the running
        // state with the permission rather than assuming it has not moved.
        quitOnClose.revalidatePermission()
        scroll.resumeIfPermitted()
        syncKeepAwake()
        customStates["everyday.mouse-scroll"] = scroll.isActive
        customStates["everyday.quit-on-close"] = quitOnClose.isActive
        syncWindowSnapping()
        syncWindowSwitching()
        syncClipboardImageConversion()
        refreshAudioApps()
    }

    // MARK: - Optional behaviours

    func isEnabled(_ behavior: OptionalBehavior) -> Bool { !disabledBehaviors.contains(behavior) }

    func setEnabled(_ behavior: OptionalBehavior, _ enabled: Bool) {
        guard enabled != isEnabled(behavior) else { return }
        defaults.set(enabled, forKey: behavior.defaultsKey)
        if enabled { disabledBehaviors.remove(behavior) } else { disabledBehaviors.insert(behavior) }
        if behavior == .clipboardHistory {
            history.setRecording(enabled)
            // Switching it off is a request to stop holding copies, so the
            // ones already held go too.
            if !enabled { history.clear() }
        }
        onBehaviorChange?(behavior, enabled)
        notice = StoreNotice(kind: .success, message: behavior.confirmation(enabled: enabled))
    }

    var isRecordingClipboard: Bool { history.isRecording }

    func setQuitOnCloseExcluded(_ excluded: Bool, bundleID: String) {
        quitOnClose.setExcluded(excluded, bundleID: bundleID)
        quitOnCloseExclusions = quitOnClose.userExcludedBundleIDs
    }

    // MARK: - Clipboard history

    func copyBack(_ entry: ClipEntry) {
        guard history.copyBack(entry) else {
            notice = StoreNotice(kind: .error, message: "That clip could not be copied.")
            return
        }
        notice = StoreNotice(kind: .success, message: "Copied back to the clipboard.")
    }

    func removeClip(_ entry: ClipEntry) { history.remove(entry) }

    /// Converted clipboard screenshots are files in the temporary folder.
    /// Clipboard history is forgotten when Switchboard quits, and they go
    /// with it.
    func discardSpooledScreenshots() { clipboardImages.discardSpool() }

    func clearClips() {
        history.clear()
        notice = StoreNotice(kind: .success, message: "Clipboard history cleared.")
    }

    // MARK: - Per-app audio

    func refreshAudioApps() {
        let latest = AppAudioEngine.runningApps()
        if latest != audioApps { audioApps = latest }
        let devices = AppAudioEngine.outputDevices()
        if devices != audioOutputDevices { audioOutputDevices = devices }
        refreshOutputDeviceVolumes()
        let defaultUID = AppAudioEngine.systemDefaultOutputUID()
        if defaultUID != systemDefaultOutputUID { systemDefaultOutputUID = defaultUID }
        let failures = appAudio.reconcile(with: latest)
        // The maintenance timer now outlives an attenuated app going quiet, so
        // an unconditional assignment would publish a change every two seconds
        // for the rest of the session.
        let volumes = Dictionary(uniqueKeysWithValues: latest.map {
            ($0.bundleID, appAudio.gain(for: $0.bundleID))
        })
        if volumes != audioVolumes { audioVolumes = volumes }
        let routes = latest.reduce(into: [String: String]()) { routes, app in
            routes[app.bundleID] = appAudio.selectedOutputUID(for: app.bundleID)
        }
        if routes != audioRoutes { audioRoutes = routes }
        updateAudioMaintenanceTimer()
        if let failure = failures.first {
            notice = StoreNotice(kind: .error, message: failure)
        }
    }

    func volume(for app: AudioApp) -> Float { audioVolumes[app.bundleID] ?? 1 }

    private func refreshOutputDeviceVolumes() {
        let volumes = audioOutputDevices.reduce(into: [String: OutputVolumeState]()) { result, device in
            do {
                result[device.uid] = try outputVolume.read(uid: device.uid)
            } catch {
                result[device.uid] = .unavailable(error.localizedDescription)
            }
        }
        if volumes != outputDeviceVolumes { outputDeviceVolumes = volumes }
    }

    func setOutputVolume(_ volume: Float, for device: AudioOutputDevice) {
        do {
            try outputVolume.set(volume, uid: device.uid)
        } catch {
            notice = StoreNotice(kind: .error, message: "\(device.name): \(error.localizedDescription)")
        }
        // Read back the hardware value, including when a write fails or the driver rounds it.
        refreshOutputDeviceVolumes()
    }

    /// The device an app is actually playing through, and the name to show for
    /// it. A chosen device that has been unplugged reads as unavailable rather
    /// than silently showing the default.
    func outputSelection(for app: AudioApp) -> (uid: String?, isMissing: Bool) {
        let selected = audioRoutes[app.bundleID]
        return (selected, AudioRouting.selectedDeviceIsMissing(
            selected: selected,
            available: Set(audioOutputDevices.map(\.uid))
        ))
    }

    func setOutputDevice(_ uid: String?, for app: AudioApp) {
        if case .failure(let error) = appAudio.setOutputDevice(uid, for: app) {
            notice = StoreNotice(kind: .error,
                                 message: "\(app.name): \(error.localizedDescription)")
        }
        audioRoutes[app.bundleID] = appAudio.selectedOutputUID(for: app.bundleID)
        updateAudioMaintenanceTimer()
    }

    var hasAdjustedAudio: Bool { appAudio.isControllingAnything }

    func resetAudioVolumes() {
        appAudio.releaseAll()
        audioVolumes = [:]
        audioRoutes = [:]
        updateAudioMaintenanceTimer()
        notice = StoreNotice(kind: .success,
                             message: "Every app is back at 100% on the default output.")
    }

    func setVolume(_ volume: Float, for app: AudioApp) {
        switch appAudio.setGain(volume, for: app) {
        case .success:
            audioVolumes[app.bundleID] = appAudio.gain(for: app.bundleID)
            updateAudioMaintenanceTimer()
        case .failure(let error):
            audioVolumes[app.bundleID] = 1
            notice = StoreNotice(kind: .error,
                                 message: "\(app.name): \(error.localizedDescription)")
            updateAudioMaintenanceTimer()
        }
    }

    /// The audio list shows whatever can currently make noise, so it needs
    /// polling while it is on screen even when nothing is being controlled.
    func setAudioListVisible(_ visible: Bool) {
        guard visible != isShowingAudioList else { return }
        isShowingAudioList = visible
        if visible {
            refreshAudioApps()
        } else {
            updateAudioMaintenanceTimer()
        }
    }

    private func resumeAudioPollingForSavedRoutes() {
        guard appAudio.hasSavedRoutes else { return }
        refreshAudioApps()
    }

    private func updateAudioMaintenanceTimer() {
        guard appAudio.needsPolling || isShowingAudioList else {
            audioMaintenanceTimer?.invalidate()
            audioMaintenanceTimer = nil
            return
        }
        guard audioMaintenanceTimer == nil else { return }

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAudioApps() }
        }
        RunLoop.main.add(timer, forMode: .common)
        audioMaintenanceTimer = timer
    }

    var visible: [Tweak] {
        if search.isEmpty {
            return catalog.filter { $0.category == category }
        }
        return catalog.filter { $0.matches(search: search) }
    }

    var visibleCategories: [Category] {
        search.isEmpty ? [category] : Category.allCases.filter { category in
            visible.contains { $0.category == category }
        }
    }

    var hasUndoRecord: Bool { !ledger.isEmpty }
    var canRestoreOriginalSettings: Bool {
        // The stored switches, not the live ones: with Accessibility revoked
        // a feature is idle but still on, and Restore must still clear it.
        hasUndoRecord || awake.isActive || scroll.isActive || quitOnClose.isActive
            || defaults.bool(forKey: Self.windowSnappingKey) || defaults.bool(forKey: Self.windowSwitchingKey)
            || appAudio.isControllingAnything
    }

    func tweaks(in category: Category) -> [Tweak] {
        visible.filter { $0.category == category }
    }

    func isOn(_ tweak: Tweak) -> Bool {
        switch tweak.behavior {
        case .preference(let preference):
            return preference.onValue.matches(values[tweak.id])
        case .keepAwake:
            return customStates[tweak.id] ?? false
        case .plainTextClipboard:
            return false
        case .mouseScrollDirection:
            return customStates[tweak.id] ?? false
        case .quitOnClose:
            return customStates[tweak.id] ?? false
        case .windowSnapping:
            return isWindowSnappingActive
        case .windowSwitching:
            return isWindowSwitchingActive
        case .regionOCR:
            return false
        case .translateCaptures:
            return defaults.bool(forKey: Self.translateKey)
        }
    }

    func selectedChoice(_ tweak: Tweak, among choices: [Choice]) -> Choice? {
        if let stored = values[tweak.id] {
            return choices.first { $0.value.matches(stored) }
        }
        return choices.first { $0.value == tweak.preference?.onValue }
    }

    func stringValue(_ tweak: Tweak) -> String? {
        values[tweak.id] as? String
    }

    func setOn(_ tweak: Tweak, _ on: Bool) {
        switch tweak.behavior {
        case .preference(let preference):
            write(on ? preference.onValue : preference.offValue, to: tweak, preference: preference)
        case .keepAwake:
            setKeepAwake(on ? .untilStopped : .off)
        case .plainTextClipboard:
            break
        case .mouseScrollDirection:
            setMouseScrollInverted(on, for: tweak)
        case .quitOnClose:
            setQuitOnClose(on, for: tweak)
        case .windowSnapping:
            setWindowSnapping(on)
        case .windowSwitching:
            setWindowSwitching(on)
        case .regionOCR:
            break
        case .translateCaptures:
            defaults.set(on, forKey: Self.translateKey)
            if #available(macOS 15.0, *) {
                notice = StoreNotice(kind: .success,
                                     message: on
                                        ? "Captured text will be translated to English."
                                        : "Captured text is copied exactly as it appears.")
            } else {
                defaults.set(false, forKey: Self.translateKey)
                notice = StoreNotice(kind: .error,
                                     message: "Translation needs macOS 15 or later.")
            }
            objectWillChange.send()
        }
    }

    private func setQuitOnClose(_ on: Bool, for tweak: Tweak) {
        guard on else {
            quitOnClose.setActive(false)
            customStates[tweak.id] = false
            notice = StoreNotice(kind: .success,
                                 message: "Red close buttons use normal macOS behaviour again.")
            return
        }
        guard QuitOnCloseController.hasPermission else {
            QuitOnCloseController.requestPermission()
            customStates[tweak.id] = false
            notice = StoreNotice(kind: .information,
                                 message: "Allow Switchboard under Accessibility, then switch this on again.",
                                 link: .accessibilitySettings)
            return
        }

        let applied = quitOnClose.setActive(true)
        customStates[tweak.id] = quitOnClose.isActive
        notice = StoreNotice(kind: applied ? .success : .error,
                             message: applied
                                ? "The red button now quits an app when it closes the last window."
                                : "macOS could not start the close-button monitor.")
    }

    /// Global shortcuts need no permission, but moving another app's windows
    /// does, so the toggle only reads as on when both agree.
    private func setWindowSnapping(_ on: Bool) {
        guard on else {
            defaults.set(false, forKey: Self.windowSnappingKey)
            syncWindowSnapping()
            notice = StoreNotice(kind: .success,
                                 message: "Window snapping is off. Its key combinations work in other apps again.")
            return
        }
        guard WindowSnapper.hasPermission else {
            WindowSnapper.requestPermission()
            syncWindowSnapping()
            notice = StoreNotice(kind: .information,
                                 message: "Allow Switchboard under Accessibility, then switch this on again.",
                                 link: .accessibilitySettings)
            return
        }
        defaults.set(true, forKey: Self.windowSnappingKey)
        // Set before syncing, so a conflict reported while the shortcuts
        // register replaces this message instead of being hidden by it.
        notice = StoreNotice(kind: .success,
                             message: "Press Control-Option with an arrow key, or hold Control while dragging a window. Every shortcut is in Keyboard Shortcuts.")
        syncWindowSnapping()
    }

    /// Accessibility can be revoked while the app runs. The preference is
    /// kept, so granting access again brings the shortcuts back.
    private func syncWindowSnapping() {
        let active = defaults.bool(forKey: Self.windowSnappingKey) && WindowSnapper.hasPermission
        guard active != isWindowSnappingActive else { return }
        isWindowSnappingActive = active
        onWindowSnappingChange?(active)
    }

    private func setWindowSwitching(_ on: Bool) {
        if on, !WindowSnapper.hasPermission {
            WindowSnapper.requestPermission()
            syncWindowSwitching()
            notice = StoreNotice(kind: .information,
                                 message: "Allow Switchboard under Accessibility, then switch this on again. Screen Recording is optional for previews.",
                                 link: .accessibilitySettings)
            return
        }
        defaults.set(on, forKey: Self.windowSwitchingKey)
        notice = StoreNotice(kind: .success, message: on
                             ? "Hold Command and press Tab to switch windows, or Option-` for this app's windows. Enable Previews in the switcher for thumbnails."
                             : "Window switching is off. The macOS Command-Tab switcher is available again.")
        syncWindowSwitching()
    }

    private func syncWindowSwitching() {
        let active = defaults.bool(forKey: Self.windowSwitchingKey) && WindowSnapper.hasPermission
        guard active != isWindowSwitchingActive else { return }
        isWindowSwitchingActive = active
        onWindowSwitchingChange?(active)
    }

    /// The scroll tap is a system-wide input hook, so the first attempt usually
    /// lands on the Accessibility prompt rather than on a working toggle.
    private func setMouseScrollInverted(_ on: Bool, for tweak: Tweak) {
        guard on else {
            scroll.setActive(false)
            customStates[tweak.id] = scroll.isActive
            notice = StoreNotice(kind: .success, message: "The mouse wheel scrolls the same way as the trackpad again.")
            return
        }
        guard ScrollInverter.hasPermission else {
            ScrollInverter.requestPermission()
            customStates[tweak.id] = false
            notice = StoreNotice(kind: .information,
                                 message: "Allow Switchboard under Accessibility, then switch this on again.",
                                 link: .accessibilitySettings)
            return
        }
        let applied = scroll.setActive(true)
        customStates[tweak.id] = scroll.isActive
        notice = StoreNotice(kind: applied ? .success : .error,
                             message: applied
                                ? "Mouse wheel flipped. Your trackpad keeps scrolling as it did."
                                : "macOS refused the scroll hook. Try toggling Accessibility access off and on.")
    }

    func select(_ value: PrefValue, for tweak: Tweak) {
        guard let preference = tweak.preference else { return }
        if case .folder = tweak.control,
           case .string(let path) = value {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: path) else {
                notice = StoreNotice(kind: .error,
                                     message: "Choose a folder that macOS can write to.")
                return
            }
        }
        write(value, to: tweak, preference: preference)
    }

    func perform(_ tweak: Tweak) {
        switch tweak.behavior {
        case .plainTextClipboard:
            let success = ClipboardCleaner.makePlainText(pasteboard: pasteboard)
            notice = StoreNotice(kind: success ? .success : .information,
                                 message: success
                                    ? "Clipboard formatting removed."
                                    : "Copy some text first, then try again.")
        case .regionOCR:
            guard canPerform(tweak) else { return }
            captureScreenText()
        default:
            break
        }
    }

    func canPerform(_ tweak: Tweak) -> Bool {
        if case .regionOCR = tweak.behavior {
            return !isSelectingScreenRegion && !isReadingScreenText
        }
        return true
    }

    /// The original text is already on the clipboard by now, so a translation
    /// that never arrives still leaves the user with something usable.
    private func requestTranslationIfWanted(for text: String) {
        guard Self.translationEnabled,
              #available(macOS 15.0, *),
              defaults.bool(forKey: Self.translateKey) else { return }
        let language = TextCapture.dominantLanguage(of: text)
        guard let language, !TextCapture.isEnglish(language) else { return }
        pendingTranslation = PendingTranslation(text: text, source: language)
    }

    func finishTranslation(_ translated: String?,
                           from source: Locale.Language,
                           failure: String?) {
        pendingTranslation = nil
        let name = Locale.current.localizedString(forLanguageCode: source.languageCode?.identifier ?? "")
            ?? "that language"
        guard let translated, !translated.isEmpty else {
            // Surface what actually went wrong instead of a blanket failure.
            notice = StoreNotice(kind: .information,
                                 message: failure.map { "Copied the original text. \($0)" }
                                    ?? "Copied the original text. \(name) could not be translated.")
            return
        }
        guard TextCapture.copyToClipboard(translated, pasteboard: pasteboard) else {
            notice = StoreNotice(kind: .error, message: "The translation could not be put on the clipboard.")
            return
        }
        if isEnabled(.clipboardHistory) {
            history.record(translated, note: "Translated from \(name)")
            showCapturedText()
        }
        notice = StoreNotice(kind: .success,
                             message: "Translated from \(name). It is in Clipboard.")
    }

    /// Text captured off the screen is unreadable if it only ever lands on the
    /// clipboard, so the panel opens on the list where it can actually be read.
    private func showCapturedText() {
        search = ""
        category = .clipboard
    }

    private func syncKeepAwake() {
        customStates["everyday.keep-awake"] = awake.isActive
        keepAwakeSpan = awake.span
        keepAwakeMode = awake.mode
    }

    func toggleKeepAwake() {
        setKeepAwake(awake.isActive ? .off : .minutes(60))
    }

    func setKeepAwake(_ mode: AwakeMode) {
        let result = awake.set(mode)
        syncKeepAwake()
        if case .failure(let failure) = result {
            notice = StoreNotice(kind: .error, message: Self.message(for: failure, starting: mode))
            return
        }
        switch mode {
        case .off:
            notice = StoreNotice(kind: .success, message: "Normal sleep settings are active again.")
        case .untilStopped:
            notice = StoreNotice(kind: .success, message: "Your Mac stays awake until you switch this off.")
        case .minutes(let minutes):
            notice = StoreNotice(kind: .success, message: "Your Mac stays awake for \(AwakeDuration.label(minutes: minutes)).")
        case .untilAppQuits(_, let name):
            notice = StoreNotice(kind: .success, message: "Your Mac stays awake until \(name) quits.")
        case .whilePluggedIn:
            notice = StoreNotice(kind: .success, message: awake.isHolding
                                 ? "Your Mac stays awake while it's plugged in."
                                 : "Your Mac will stay awake once it's plugged in.")
        }
    }

    func setKeepAwakeAllowsDisplaySleep(_ allowed: Bool) {
        let wasActive = awake.isActive
        defaults.set(allowed, forKey: Self.awakeDisplaySleepKey)
        keepAwakeAllowsDisplaySleep = allowed
        awake.allowsDisplaySleep = allowed
        syncKeepAwake()
        if wasActive && !awake.isActive {
            notice = StoreNotice(kind: .error, message: "macOS could not change the sleep assertion, so keep awake is off.")
            return
        }
        notice = StoreNotice(kind: .success, message: allowed
                             ? "Keep awake now lets the display sleep."
                             : "Keep awake now keeps the display on too.")
    }

    private static func message(for failure: AwakeStartFailure, starting mode: AwakeMode) -> String {
        switch failure {
        case .appNotRunning:
            if case .untilAppQuits(_, let name) = mode { return "\(name) has already quit, so keep awake is off." }
            return "That app has already quit, so keep awake is off."
        case .assertionRefused, .invalidDuration:
            return "macOS could not change the sleep assertion."
        case .powerChangesUnavailable:
            return "macOS isn't reporting power changes, so keep awake can't follow the power adapter."
        }
    }

    /// The picker UI runs full screen, so the popover closes underneath it and
    /// comes back when the crosshair has gone.
    private func captureScreenText() {
        isSelectingScreenRegion = true
        onScreenSelectionBegan?()
        screenText.selectRegion { [weak self] selection in
            guard let self else { return }
            self.isSelectingScreenRegion = false
            switch selection {
            case .success(let picture): self.readText(in: picture)
            case .failure(let error): self.reportCaptureFailure(error)
            }
            // However this went -- a picture to read, nothing chosen, or a
            // refusal -- the panel comes back so what happened is readable.
            self.onScreenSelectionEnded?()
        }
    }

    /// Reading runs in the background while the app carries on.
    ///
    /// It used to count as part of the capture, which kept the panel shut and
    /// every shortcut ignored until Vision answered. The first read on a
    /// system build takes about half a minute while macOS compiles its
    /// models, and for all of it Switchboard looked hung.
    private func readText(in picture: Data) {
        isReadingScreenText = true
        notice = StoreNotice(kind: .information,
                             message: "Reading the text… The first read can take up to a minute while macOS gets text recognition ready.")
        screenText.recognise(picture) { [weak self] result in
            guard let self else { return }
            self.isReadingScreenText = false
            switch result {
            case .success(let text): self.deliverCapturedText(text)
            case .failure(let error): self.reportCaptureFailure(error)
            }
        }
    }

    private func deliverCapturedText(_ text: String) {
        guard TextCapture.copyToClipboard(text, pasteboard: pasteboard) else {
            notice = StoreNotice(kind: .error, message: "The text could not be put on the clipboard.")
            return
        }
        let lines = text.lineCount
        notice = StoreNotice(kind: .success, message: "Copied \(lines) line\(lines == 1 ? "" : "s") of text.")
        // With history off nothing is kept, so there is no list to show the text in.
        if isEnabled(.clipboardHistory) {
            history.record(text, note: "Captured from the screen")
            showCapturedText()
        }
        requestTranslationIfWanted(for: text)
    }

    private func reportCaptureFailure(_ error: Error) {
        let reason = error as? TextCapture.CaptureError
        notice = StoreNotice(kind: reason == .cancelled ? .information : .error,
                             message: error.localizedDescription,
                             link: reason == .permissionDenied ? .screenRecordingSettings : nil)
    }

    /// macOS compiles its recognition models the first time an app reads
    /// text on a given system build. Doing that shortly after launch, in the
    /// background, keeps it off someone's first capture.
    private func prepareTextRecognitionOncePerSystemBuild() {
        let systemBuild = ProcessInfo.processInfo.operatingSystemVersionString
        guard defaults.string(forKey: Self.recognitionPreparedKey) != systemBuild else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + screenText.prepareDelaySeconds) { [weak self] in
            self?.screenText.prepare { [weak self] didRead in
                // Left unrecorded after a failure, so the next launch tries again.
                guard didRead, let self else { return }
                self.defaults.set(systemBuild, forKey: Self.recognitionPreparedKey)
            }
        }
    }

    private func write(_ value: PrefValue?, to tweak: Tweak, preference: PreferenceSpec) {
        for key in preference.keys {
            ledger.capture(domain: preference.domain, key: key)
        }
        let synchronized = PreferenceStore.write(value,
                                                  domain: preference.domain,
                                                  keys: preference.keys)
        reread(tweak, preference: preference)

        let accepted: Bool
        if let value {
            accepted = value.matches(values[tweak.id])
        } else {
            accepted = preference.keys.allSatisfy {
                PreferenceStore.storedValue(domain: preference.domain, key: $0) == nil
            }
        }

        guard synchronized && accepted else {
            notice = StoreNotice(kind: .error,
                                 message: "macOS did not accept this change.")
            return
        }

        if let target = preference.restart {
            pendingRestarts.insert(target)
            notice = StoreNotice(kind: .information,
                                 message: "Saved. Restart \(target.label) to apply it.")
        } else {
            notice = StoreNotice(kind: .success,
                                 message: tweak.successMessage ?? "Change applied.")
        }
        if tweak.id == "capture.clipboard" || tweak.id == "capture.format" {
            syncClipboardImageConversion()
        }
    }

    private func reread(_ tweak: Tweak, preference: PreferenceSpec) {
        if let current = PreferenceStore.effectiveValue(domain: preference.domain, keys: preference.keys) {
            values[tweak.id] = current
        } else {
            values.removeValue(forKey: tweak.id)
        }
    }

    func restoreDefaults() {
        guard canRestoreOriginalSettings else { return }
        pendingRestarts.formUnion(ledger.affectedTargets(in: catalog))
        let preferencesRestored = ledger.restoreAll()
        awake.set(.off)
        let awakeRestored = !awake.isActive
        let scrollRestored = scroll.setActive(false)
        let quitRestored = quitOnClose.setActive(false)
        defaults.set(false, forKey: Self.windowSnappingKey)
        defaults.set(false, forKey: Self.windowSwitchingKey)
        appAudio.releaseAll()
        audioVolumes.removeAll()
        audioRoutes.removeAll()
        updateAudioMaintenanceTimer()
        let restored = preferencesRestored && awakeRestored && scrollRestored && quitRestored
        refresh()
        notice = StoreNotice(kind: restored ? .success : .error,
                             message: restored
                                ? "Original settings restored."
                                : "Some original settings could not be restored.")
    }

    func applyPendingRestarts() {
        var completed: Set<RestartTarget> = []
        for target in pendingRestarts where SystemRestart.killall(target) {
            completed.insert(target)
        }
        pendingRestarts.subtract(completed)
        refresh()

        if pendingRestarts.isEmpty {
            notice = StoreNotice(kind: .success, message: "Changes are now active.")
        } else {
            notice = StoreNotice(kind: .error,
                                 message: "A system service could not be restarted. Try again.")
        }
    }

    private func syncClipboardImageConversion() {
        let copiesToClipboard = PrefValue.string("clipboard")
            .matches(values["capture.clipboard"])
        let format = values["capture.format"] as? String ?? "png"
        clipboardImages.configure(enabled: copiesToClipboard, format: format)
    }

    deinit {
        audioMaintenanceTimer?.invalidate()
        if let accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(accessibilityObserver)
        }
        if let appLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appLaunchObserver)
        }
    }
}
