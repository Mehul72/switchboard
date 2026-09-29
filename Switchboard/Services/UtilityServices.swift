import AppKit
import Foundation
import IOKit.ps

/// What is powering the Mac right now.
struct PowerSnapshot: Equatable {
    let hasInternalBattery: Bool
    /// Nil when macOS does not say which source is in use.
    let isOnExternalPower: Bool?

    /// Read once per launch: a Mac does not gain or lose its battery while running.
    static let machineHasBattery = current().hasInternalBattery

    static func current() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSnapshot(hasInternalBattery: false, isOnExternalPower: nil)
        }
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        let hasBattery = sources.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return PowerSnapshot(hasInternalBattery: hasBattery,
                             isOnExternalPower: providing.map { $0 == kIOPSACPowerValue })
    }
}

/// How long the Mac has been held awake, and when that ends.
struct AwakeSpan: Equatable {
    let startedAt: Date
    /// Nil when the span runs until the user stops it or `condition` ends it.
    let endsAt: Date?
    var condition: AwakeCondition?
}

/// Something other than the clock that decides when keep awake ends.
enum AwakeCondition: Equatable {
    case appRuns(name: String)
    /// `holding` is false while the Mac is on battery and keep awake waits.
    case pluggedIn(holding: Bool)
}

/// Wording for the keep-awake row. Minute granularity, because a second-by-
/// second countdown on a row people glance at reads as noise.
enum AwakeStatus {
    /// Nil once a timed span has run out, so the row stops claiming the Mac is
    /// awake in the moment between expiry and the timer that clears it.
    static func text(for span: AwakeSpan, now: Date = Date()) -> String? {
        switch span.condition {
        case .appRuns(let name): return "On until \(name) quits"
        case .pluggedIn(holding: true): return "On while plugged in"
        case .pluggedIn(holding: false): return "Paused until plugged in"
        case nil: break
        }
        guard let endsAt = span.endsAt else {
            let elapsed = now.timeIntervalSince(span.startedAt)
            return "On for " + phrase(minutes: Int((elapsed / 60).rounded(.down)))
        }
        let secondsLeft = endsAt.timeIntervalSince(now)
        guard secondsLeft > 0 else { return nil }
        // Rounded up so picking "30 minutes" does not immediately read as 29.
        return "Ends in " + phrase(minutes: Int((secondsLeft / 60).rounded(.up)))
    }

    private static func phrase(minutes: Int) -> String {
        guard minutes >= 1 else { return "less than a minute" }
        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        guard hours >= 1 else { return pluralized(minutes, "minute") }
        guard leftoverMinutes >= 1 else { return pluralized(hours, "hour") }
        return pluralized(hours, "hour") + " " + pluralized(leftoverMinutes, "minute")
    }

    private static func pluralized(_ amount: Int, _ noun: String) -> String {
        "\(amount) \(noun)\(amount == 1 ? "" : "s")"
    }
}

/// What keeps the Mac awake, and so what has to happen before it may sleep.
enum AwakeMode: Equatable {
    case off
    case minutes(Int)
    case untilStopped
    case untilAppQuits(pid: pid_t, name: String)
    /// Holds the Mac awake only while it runs on its power adapter.
    case whilePluggedIn
}

enum AwakeStartFailure: Error, Equatable {
    case invalidDuration
    case assertionRefused
    case appNotRunning
    /// macOS would not report power changes, so the mode could never resume.
    case powerChangesUnavailable
}

/// The fixed spans offered beside the open-ended and conditional modes.
enum AwakeDuration {
    static let choices = [30, 60, 120]

    static func label(minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : (minutes == 60 ? "1 hour" : "\(minutes / 60) hours")
    }
}

/// Why keep awake ended by itself.
enum AwakeFinish: Equatable {
    case timeUp
    case appQuit(name: String)
}

/// An app keep awake can wait on.
struct AwakeApp: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    var id: pid_t { pid }

    /// Regular apps only: background agents rarely quit, and Finder never does.
    static func running() -> [AwakeApp] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular && !app.isTerminated
                    && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    && app.bundleIdentifier != "com.apple.finder"
            }
            .compactMap { app in app.localizedName.map { AwakeApp(pid: app.processIdentifier, name: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Everything keep awake needs from macOS, so tests can stand in for power
/// changes and app exits without touching the real sleep settings.
struct AwakeEnvironment {
    /// Starts holding the Mac awake. Nil if macOS refused.
    var beginHold: (_ allowDisplaySleep: Bool) -> AnyObject?
    var endHold: (AnyObject) -> Void
    var power: () -> PowerSnapshot
    var isRunning: (pid_t) -> Bool
    /// Calls back on the main thread when the power source changes, until the
    /// returned token is released.
    var observePower: (@escaping () -> Void) -> AnyObject?
    /// Calls back on the main thread with each app that exits, until the
    /// returned token is released.
    var observeExits: (@escaping (pid_t) -> Void) -> AnyObject?

    static let live = AwakeEnvironment(
        beginHold: { allowDisplaySleep in
            let options: ProcessInfo.ActivityOptions = allowDisplaySleep
                ? [.idleSystemSleepDisabled]
                : [.idleSystemSleepDisabled, .idleDisplaySleepDisabled]
            return ProcessInfo.processInfo.beginActivity(options: options, reason: "Switchboard Keep Awake")
        },
        endHold: { hold in
            guard let activity = hold as? NSObjectProtocol else { return }
            ProcessInfo.processInfo.endActivity(activity)
        },
        power: PowerSnapshot.current,
        isRunning: { pid in NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false },
        observePower: { PowerSourceObserver(onChange: $0) },
        observeExits: { AppExitObserver(onExit: $0) }
    )
}

/// Holds a power assertion until the chosen mode ends. An open-ended assertion
/// is easy to switch on and forget about for days, so how it ends is part of
/// the control rather than a separate thing to remember.
final class AwakeController {
    private let environment: AwakeEnvironment
    private(set) var mode: AwakeMode = .off
    private var hold: AnyObject?
    private var holdStartedAt: Date?
    private var expiry: Timer?
    private var watcher: AnyObject?
    private(set) var endsAt: Date?

    /// Fires on the main thread when keep awake ends without being switched off.
    var onFinish: ((AwakeFinish) -> Void)?
    /// Fires on the main thread when the power adapter pauses or resumes
    /// "While plugged in", so the row stops describing the old state.
    var onHoldChange: (() -> Void)?

    /// Keeps the Mac running but lets the screen turn off, for long downloads
    /// or renders nobody is watching.
    var allowsDisplaySleep = false {
        didSet {
            guard allowsDisplaySleep != oldValue, let current = hold else { return }
            // The assertion's options are fixed once taken, so swap it for a new
            // one and keep the original start time.
            let startedAt = holdStartedAt
            environment.endHold(current)
            hold = environment.beginHold(allowsDisplaySleep)
            guard hold != nil else {
                turnOff()
                return
            }
            holdStartedAt = startedAt
        }
    }

    init(environment: AwakeEnvironment = .live) {
        self.environment = environment
    }

    var isActive: Bool { mode != .off }
    var isHolding: Bool { hold != nil }

    /// What the row reports. Nil when off.
    var span: AwakeSpan? {
        let startedAt = holdStartedAt ?? .distantPast
        switch mode {
        case .off:
            return nil
        case .minutes:
            return AwakeSpan(startedAt: startedAt, endsAt: endsAt)
        case .untilStopped:
            return AwakeSpan(startedAt: startedAt, endsAt: nil)
        case .untilAppQuits(_, let name):
            return AwakeSpan(startedAt: startedAt, endsAt: nil, condition: .appRuns(name: name))
        case .whilePluggedIn:
            return AwakeSpan(startedAt: startedAt, endsAt: nil, condition: .pluggedIn(holding: isHolding))
        }
    }

    /// Keep awake is off after any failure except an invalid duration, which
    /// leaves the current mode alone.
    @discardableResult
    func set(_ newMode: AwakeMode) -> Result<Void, AwakeStartFailure> {
        if case .minutes(let minutes) = newMode, minutes <= 0 { return .failure(.invalidDuration) }
        expiry?.invalidate()
        expiry = nil
        endsAt = nil
        watcher = nil

        switch newMode {
        case .off:
            turnOff()
            return .success(())
        case .minutes(let minutes):
            guard takeHold() else { return fail(.assertionRefused) }
            let deadline = Date().addingTimeInterval(TimeInterval(minutes) * 60)
            endsAt = deadline
            let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
                self?.finish(.timeUp)
            }
            RunLoop.main.add(timer, forMode: .common)
            expiry = timer
        case .untilStopped:
            guard takeHold() else { return fail(.assertionRefused) }
        case .untilAppQuits(let pid, let name):
            // Watch before checking, so an exit in between is not missed.
            watcher = environment.observeExits { [weak self] exited in
                guard exited == pid else { return }
                self?.finish(.appQuit(name: name))
            }
            guard environment.isRunning(pid) else { return fail(.appNotRunning) }
            guard takeHold() else { return fail(.assertionRefused) }
        case .whilePluggedIn:
            // Without the notification it would never resume after unplugging.
            watcher = environment.observePower { [weak self] in
                guard let self else { return }
                let wasHolding = self.isHolding
                // A refused assertion here leaves the mode waiting, as on battery.
                self.followPower()
                if self.isHolding != wasHolding { self.onHoldChange?() }
            }
            guard watcher != nil else { return fail(.powerChangesUnavailable) }
            mode = newMode
            guard followPower() else { return fail(.assertionRefused) }
            return .success(())
        }
        mode = newMode
        return .success(())
    }

    /// Holds on external power and lets go on battery. False only when macOS
    /// refuses the assertion.
    @discardableResult
    private func followPower() -> Bool {
        guard mode == .whilePluggedIn else { return true }
        guard environment.power().isOnExternalPower == true else {
            releaseHold()
            return true
        }
        return takeHold()
    }

    private func finish(_ reason: AwakeFinish) {
        guard isActive else { return }
        set(.off)
        onFinish?(reason)
    }

    private func fail(_ reason: AwakeStartFailure) -> Result<Void, AwakeStartFailure> {
        turnOff()
        return .failure(reason)
    }

    private func turnOff() {
        expiry?.invalidate()
        expiry = nil
        endsAt = nil
        watcher = nil
        releaseHold()
        mode = .off
    }

    /// Changing the mode later must not restart the clock: the Mac has been
    /// awake since this assertion began, not since the last edit.
    private func takeHold() -> Bool {
        guard hold == nil else { return true }
        hold = environment.beginHold(allowsDisplaySleep)
        holdStartedAt = hold == nil ? nil : Date()
        return hold != nil
    }

    private func releaseHold() {
        if let hold { environment.endHold(hold) }
        hold = nil
        holdStartedAt = nil
    }

    deinit {
        expiry?.invalidate()
        releaseHold()
    }
}

/// Wraps IOKit's power-source notification, which fires on every change to
/// any power source, including the charge level, so callers re-read the state.
private final class PowerSourceObserver {
    private let onChange: () -> Void
    private var source: CFRunLoopSource?

    init?(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerSourceObserver>.fromOpaque(context).takeUnretainedValue().onChange()
        }, context)?.takeRetainedValue() else { return nil }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    deinit {
        guard let source else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
    }
}

private final class AppExitObserver {
    private let token: NSObjectProtocol

    init(onExit: @escaping (pid_t) -> Void) {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            onExit(app.processIdentifier)
        }
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(token) }
}

enum ClipboardCleaner {
    static func makePlainText(pasteboard: NSPasteboard = .general) -> Bool {
        let changeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return false }
        let types = Set(pasteboard.pasteboardItems?.flatMap(\.types) ?? [])
            .union(pasteboard.types ?? [])
        let replacement = NSPasteboardItem()
        guard replacement.setString(text, forType: .string) else { return false }
        // Formatting cleanup must not turn a private copy into recordable text.
        for marker in types.intersection(ClipboardHistory.excludedTypes) {
            guard replacement.setData(Data(), forType: marker) else { return false }
        }
        guard pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([replacement])
    }
}
