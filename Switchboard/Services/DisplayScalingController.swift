import AppKit
import Combine
import OSLog

@MainActor
final class DisplayScalingController: ObservableObject {
    @Published private(set) var displays: [ScalingDisplay] = []
    @Published var selectedDisplayID: UInt32? {
        didSet { selectAvailablePreset() }
    }
    @Published var selectedPresetID = ""
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var activeDisplayID: UInt32?
    @Published private(set) var activePreset: DisplayScalePreset?
    @Published private(set) var confirmationSeconds: Int?

    static let confirmationDuration: TimeInterval = 20
    private let backend: DisplayScalingBackendProtocol
    private let now: () -> TimeInterval
    private let automaticallyTick: Bool
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "display-scaling")
    private var operation: Task<Void, Never>?
    private var countdown: Task<Void, Never>?
    private var displayChange: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var confirmationDeadline: TimeInterval?
    private var isShuttingDown = false

    init(backend: DisplayScalingBackendProtocol,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallyTick: Bool = true, observeSystem: Bool = true) {
        self.backend = backend
        self.now = now
        self.automaticallyTick = automaticallyTick
        if observeSystem { observeDisplayChanges() }
        refresh()
    }

    var selectedDisplay: ScalingDisplay? { displays.first { $0.id == selectedDisplayID } }
    var presets: [DisplayScalePreset] {
        guard let display = selectedDisplay else { return [] }
        return DisplayScalePreset.choices(width: display.nativeWidth, height: display.nativeHeight)
    }
    var selectedPreset: DisplayScalePreset? { presets.first { $0.id == selectedPresetID } }
    var isActive: Bool { activeDisplayID != nil }
    var canPreview: Bool {
        guard !isBusy, !isShuttingDown, confirmationSeconds == nil,
              let display = selectedDisplay, !display.isBuiltIn,
              display.unavailableReason == nil, selectedPreset != nil else { return false }
        return true
    }

    func refresh() {
        guard !isBusy, !isShuttingDown else { return }
        do {
            displays = try backend.displays()
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = displays.first { !$0.isBuiltIn && $0.unavailableReason == nil }?.id
                    ?? displays.first { !$0.isBuiltIn }?.id ?? displays.first?.id
            }
            selectAvailablePreset()
        } catch {
            report(error)
        }
    }

    @discardableResult
    func preview() -> Task<Void, Never>? {
        guard canPreview, let display = selectedDisplay, let preset = selectedPreset else { return nil }
        if isActive, !restoreSession(message: nil) { return nil }
        errorMessage = nil
        statusMessage = "Preparing your display…"
        isBusy = true
        activeDisplayID = display.id
        activePreset = preset
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.backend.start(displayID: display.id, preset: preset)
                try Task.checkCancellation()
                guard !self.isShuttingDown, self.backend.isSessionValid() else {
                    throw DisplayScalingError.unavailable("The display changed before scaling was ready. Try again after reconnecting it.")
                }
                self.isBusy = false
                self.confirmationDeadline = self.now() + Self.confirmationDuration
                self.confirmationSeconds = Int(Self.confirmationDuration)
                self.statusMessage = "Keep this size if everything is readable. Otherwise it will revert automatically."
                self.startCountdown()
                self.logger.info("Started HiDPI preview at \(preset.width) by \(preset.height)")
            } catch {
                let cancelled = error is CancellationError
                let restored = self.restoreSession(message: cancelled ? "Scaling cancelled. Original settings restored." : nil)
                if !cancelled {
                    if restored { self.report(error) }
                    else {
                        self.errorMessage = "\(error.localizedDescription) \(self.errorMessage ?? "")"
                    }
                }
                self.isBusy = false
            }
        }
        operation = task
        return task
    }

    func keep() {
        guard !isBusy, let deadline = confirmationDeadline else { return }
        guard now() < deadline, backend.isSessionValid() else {
            restore()
            return
        }
        clearCountdown()
        statusMessage = "HiDPI scaling is on. Restore Original returns to your previous settings."
        logger.info("HiDPI preview confirmed")
    }

    func restore() {
        if isBusy {
            operation?.cancel()
            statusMessage = "Cancelling scaling…"
            return
        }
        if restoreSession(message: "Original display settings restored.") { refresh() }
    }

    func windowWillClose() {
        if isBusy || confirmationSeconds != nil { restore() }
    }

    func tick() {
        guard let deadline = confirmationDeadline, !isBusy else { return }
        let remaining = deadline - now()
        if remaining <= 0 || !backend.isSessionValid() {
            restore()
        } else {
            confirmationSeconds = Int(ceil(remaining))
        }
    }

    func displaysDidChange() {
        guard !isBusy, !isShuttingDown else { return }
        if isActive && !backend.isSessionValid() {
            _ = restoreSession(message: "Scaling stopped because the display connection changed.")
        }
        refresh()
    }

    func prepareForSleep() {
        if isBusy || isActive { restore() }
    }

    func shutdown() {
        isShuttingDown = true
        operation?.cancel()
        displayChange?.cancel()
        _ = restoreSession(message: nil)
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func selectAvailablePreset() {
        let choices = presets
        guard !choices.contains(where: { $0.id == selectedPresetID }) else { return }
        selectedPresetID = choices.first(where: { $0.percent == 125 })?.id ?? choices.first?.id ?? ""
    }

    @discardableResult
    private func restoreSession(message: String?) -> Bool {
        clearCountdown()
        do {
            try backend.stop()
            activeDisplayID = nil
            activePreset = nil
            errorMessage = nil
            statusMessage = message
            return true
        } catch {
            report(error)
            statusMessage = "Restoration needs attention. Try Restore Original again, or quit Switchboard."
            return false
        }
    }

    private func clearCountdown() {
        countdown?.cancel()
        countdown = nil
        confirmationDeadline = nil
        confirmationSeconds = nil
    }

    private func startCountdown() {
        guard automaticallyTick else { return }
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        logger.error("Display scaling failed: \(error.localizedDescription, privacy: .public)")
    }

    private func observeDisplayChanges() {
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleDisplayRefresh() }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.prepareForSleep() }
            }))
        }
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleDisplayRefresh() }
        }))
    }

    private func scheduleDisplayRefresh() {
        displayChange?.cancel()
        displayChange = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.displaysDidChange()
        }
    }
}
