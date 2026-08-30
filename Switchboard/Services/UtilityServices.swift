import AppKit
import Foundation

/// Holds a power assertion for a chosen span. An open-ended assertion is easy
/// to switch on and forget about for days, so the duration is part of the
/// control rather than a separate thing to remember.
final class AwakeController {
    /// Minutes to stay awake. `0` is off; `indefinite` never expires.
    static let indefinite = -1

    private var activity: NSObjectProtocol?
    private var expiry: Timer?
    private(set) var minutes = 0
    private(set) var endsAt: Date?

    /// Fires on the main thread when a timed span runs out, so the UI can
    /// stop claiming the Mac is being kept awake.
    var onExpiry: (() -> Void)?

    var isActive: Bool { activity != nil }

    /// Remaining time, for the subtitle. Nil when off or open-ended.
    var remaining: TimeInterval? {
        guard let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    @discardableResult
    func setActive(_ active: Bool) -> Bool {
        set(minutes: active ? Self.indefinite : 0)
    }

    @discardableResult
    func set(minutes newMinutes: Int) -> Bool {
        guard newMinutes == 0 || newMinutes == Self.indefinite || newMinutes > 0 else {
            return false
        }

        expiry?.invalidate()
        expiry = nil
        endsAt = nil

        guard newMinutes != 0 else {
            release()
            minutes = 0
            return !isActive
        }

        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "Switchboard Keep Awake"
            )
        }
        guard isActive else { minutes = 0; return false }
        minutes = newMinutes

        if newMinutes > 0 {
            let deadline = Date().addingTimeInterval(TimeInterval(newMinutes) * 60)
            endsAt = deadline
            let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.set(minutes: 0)
                self.onExpiry?()
            }
            RunLoop.main.add(timer, forMode: .common)
            expiry = timer
        }
        return true
    }

    private func release() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    deinit {
        expiry?.invalidate()
        release()
    }
}

enum ClipboardCleaner {
    static func makePlainText() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}
