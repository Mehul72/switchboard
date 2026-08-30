import Foundation
import SwiftUI

struct StoreNotice: Identifiable, Equatable {
    enum Kind { case success, information, error }
    let id = UUID()
    let kind: Kind
    let message: String
}

final class TweakStore: ObservableObject {
    let catalog = TweakCatalog.all

    @Published var search = ""
    @Published var category: Category = .everyday
    @Published private(set) var pendingRestarts: Set<RestartTarget> = []
    @Published private(set) var values: [String: Any] = [:]
    @Published private(set) var customStates: [String: Bool] = [:]
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
    @Published private(set) var isCapturingText = false

    private let ledger = UndoLedger()
    private let awake = AwakeController()
    private let scroll = ScrollInverter()
    private let quitOnClose = QuitOnCloseController()
    private let clipboardImages = ClipboardImageConverter()
    private let appAudio = AppAudioEngine()
    private let history = ClipboardHistory()
    private static let translateKey = "TranslateCapturedText"
    /// Master switch for the capture translation feature. While false the
    /// toggle is absent from the catalog and captures are never translated,
    /// even if the preference was switched on earlier.
    static let translationEnabled = false
    private var audioMaintenanceTimer: Timer?
    private var accessibilityObserver: NSObjectProtocol?

    init() {
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
        history.onChange = { [weak self] in
            guard let self else { return }
            self.clips = self.history.entries
        }
        history.setRecording(true)
        awake.onExpiry = { [weak self] in
            guard let self else { return }
            self.customStates["everyday.keep-awake"] = false
            self.notice = StoreNotice(kind: .information,
                                      message: "Keep awake finished. Normal sleep settings are back.")
        }
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
            if let value = PreferenceStore.effectiveValue(domain: preference.domain, key: preference.key) {
                latest[tweak.id] = value
            }
        }
        values = latest
        quitOnClose.revalidatePermission()
        customStates["everyday.keep-awake"] = awake.isActive
        customStates["everyday.mouse-scroll"] = scroll.isActive
        customStates["everyday.quit-on-close"] = quitOnClose.isActive
        syncClipboardImageConversion()
        refreshAudioApps()
    }

    // MARK: - Per-app audio

    // MARK: - Clipboard history

    func copyBack(_ entry: ClipEntry) {
        guard history.copyBack(entry) else {
            notice = StoreNotice(kind: .error, message: "That clip could not be copied.")
            return
        }
        notice = StoreNotice(kind: .success, message: "Copied back to the clipboard.")
    }

    func removeClip(_ entry: ClipEntry) { history.remove(entry) }

    func clearClips() {
        history.clear()
        notice = StoreNotice(kind: .success, message: "Clipboard history cleared.")
    }

    func refreshAudioApps() {
        let latest = AppAudioEngine.runningApps()
        if latest != audioApps { audioApps = latest }
        let failures = appAudio.reconcile(with: latest)
        audioVolumes = Dictionary(uniqueKeysWithValues: latest.map {
            ($0.bundleID, appAudio.gain(for: $0.bundleID))
        })
        updateAudioMaintenanceTimer()
        if let failure = failures.first {
            notice = StoreNotice(kind: .error, message: failure)
        }
    }

    func volume(for app: AudioApp) -> Float { audioVolumes[app.bundleID] ?? 1 }

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

    private func updateAudioMaintenanceTimer() {
        guard appAudio.isControllingAnything else {
            audioMaintenanceTimer?.invalidate()
            audioMaintenanceTimer = nil
            return
        }
        guard audioMaintenanceTimer == nil else { return }

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshAudioApps()
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
        hasUndoRecord || awake.isActive || scroll.isActive || quitOnClose.isActive
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
        case .regionOCR:
            return false
        case .translateCaptures:
            return UserDefaults.standard.bool(forKey: Self.translateKey)
        }
    }

    func selectedChoice(_ tweak: Tweak, among choices: [Choice]) -> Choice? {
        if case .keepAwake = tweak.behavior {
            return choices.first { $0.value == .int(awake.isActive ? awake.minutes : 0) }
        }
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
            let applied = awake.setActive(on)
            customStates[tweak.id] = awake.isActive
            notice = StoreNotice(kind: applied ? .success : .error,
                                 message: applied
                                    ? (on ? "Your Mac will stay awake while Switchboard is running." : "Normal sleep settings are active again.")
                                    : "macOS could not change the sleep assertion.")
        case .plainTextClipboard:
            break
        case .mouseScrollDirection:
            setMouseScrollInverted(on, for: tweak)
        case .quitOnClose:
            setQuitOnClose(on, for: tweak)
        case .regionOCR:
            break
        case .translateCaptures:
            UserDefaults.standard.set(on, forKey: Self.translateKey)
            if #available(macOS 15.0, *) {
                notice = StoreNotice(kind: .success,
                                     message: on
                                        ? "Captured text will be translated to English."
                                        : "Captured text is copied exactly as it appears.")
            } else {
                UserDefaults.standard.set(false, forKey: Self.translateKey)
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
                                 message: "Allow Switchboard under Accessibility, then switch this on again.")
            return
        }

        let applied = quitOnClose.setActive(true)
        customStates[tweak.id] = quitOnClose.isActive
        notice = StoreNotice(kind: applied ? .success : .error,
                             message: applied
                                ? "The red button now quits an app instead of leaving it running."
                                : "macOS could not start the close-button monitor.")
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
                                 message: "Allow Switchboard under Accessibility, then switch this on again.")
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
        if case .keepAwake = tweak.behavior {
            guard case .int(let minutes) = value else { return }
            setKeepAwake(minutes: minutes)
            return
        }
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
            let success = ClipboardCleaner.makePlainText()
            notice = StoreNotice(kind: success ? .success : .information,
                                 message: success
                                    ? "Clipboard formatting removed."
                                    : "Copy some text first, then try again.")
        case .regionOCR:
            guard !isCapturingText else { return }
            captureScreenText()
        default:
            break
        }
    }

    func canPerform(_ tweak: Tweak) -> Bool {
        if case .regionOCR = tweak.behavior {
            return !isCapturingText
        }
        return true
    }

    /// The original text is already on the clipboard by now, so a translation
    /// that never arrives still leaves the user with something usable.
    private func requestTranslationIfWanted(for text: String) {
        guard Self.translationEnabled,
              #available(macOS 15.0, *),
              UserDefaults.standard.bool(forKey: Self.translateKey) else { return }
        let language = TextCapture.dominantLanguage(of: text)
        guard let language, !TextCapture.isEnglish(language) else { return }
        pendingTranslation = PendingTranslation(text: text, source: language)
    }

    @MainActor
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
        guard TextCapture.copyToClipboard(translated) else {
            notice = StoreNotice(kind: .error, message: "The translation could not be put on the clipboard.")
            return
        }
        history.record(translated, note: "Translated from \(name)")
        showCapturedText()
        notice = StoreNotice(kind: .success,
                             message: "Translated from \(name). It is in Clipboard.")
    }

    /// Text captured off the screen is unreadable if it only ever lands on the
    /// clipboard, so the panel opens on the list where it can actually be read.
    private func showCapturedText() {
        search = ""
        category = .clipboard
    }

    private func setKeepAwake(minutes: Int) {
        let applied = awake.set(minutes: minutes)
        customStates["everyday.keep-awake"] = awake.isActive
        guard applied else {
            notice = StoreNotice(kind: .error, message: "macOS could not change the sleep assertion.")
            return
        }
        switch minutes {
        case 0:
            notice = StoreNotice(kind: .success, message: "Normal sleep settings are active again.")
        case AwakeController.indefinite:
            notice = StoreNotice(kind: .success, message: "Your Mac stays awake until you switch this off.")
        default:
            let label = minutes < 60 ? "\(minutes) minutes" : (minutes == 60 ? "1 hour" : "\(minutes / 60) hours")
            notice = StoreNotice(kind: .success, message: "Your Mac stays awake for \(label).")
        }
    }

    /// The picker UI runs full screen, so the popover closes underneath it and
    /// the result has to be reported the next time it opens.
    private func captureScreenText() {
        isCapturingText = true
        onScreenSelectionBegan?()
        TextCapture.selectRegion { [weak self] result in
            guard let self else { return }
            self.isCapturingText = false
            // However this ends -- copied, empty, or cancelled -- the panel
            // comes back so the result is actually readable.
            defer { self.onScreenSelectionEnded?() }
            switch result {
            case .success(let text):
                guard TextCapture.copyToClipboard(text) else {
                    self.notice = StoreNotice(kind: .error, message: "The text could not be put on the clipboard.")
                    return
                }
                let lines = text.split(separator: "\n").count
                self.notice = StoreNotice(kind: .success,
                                          message: "Copied \(lines) line\(lines == 1 ? "" : "s") of text.")
                self.history.record(text, note: "Captured from the screen")
                self.showCapturedText()
                self.requestTranslationIfWanted(for: text)
            case .failure(let error):
                let cancelled = (error as? TextCapture.CaptureError) == .cancelled
                self.notice = StoreNotice(kind: cancelled ? .information : .error,
                                          message: error.localizedDescription)
            }
        }
    }

    private func write(_ value: PrefValue?, to tweak: Tweak, preference: PreferenceSpec) {
        ledger.capture(domain: preference.domain, key: preference.key)
        let synchronized = PreferenceStore.write(value,
                                                  domain: preference.domain,
                                                  key: preference.key)
        reread(tweak, preference: preference)

        let accepted: Bool
        if let value {
            accepted = value.matches(values[tweak.id])
        } else {
            accepted = PreferenceStore.storedValue(domain: preference.domain,
                                                    key: preference.key) == nil
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
        if let current = PreferenceStore.effectiveValue(domain: preference.domain, key: preference.key) {
            values[tweak.id] = current
        } else {
            values.removeValue(forKey: tweak.id)
        }
    }

    func restoreDefaults() {
        guard canRestoreOriginalSettings else { return }
        pendingRestarts.formUnion(ledger.affectedTargets(in: catalog))
        let preferencesRestored = ledger.restoreAll()
        let awakeRestored = awake.setActive(false)
        let scrollRestored = scroll.setActive(false)
        let quitRestored = quitOnClose.setActive(false)
        appAudio.releaseAll()
        audioVolumes.removeAll()
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
    }
}
