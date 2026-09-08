import AppKit
import Foundation

/// How long the Mac has been held awake, and when that ends.
struct AwakeSpan: Equatable {
    let startedAt: Date
    /// Nil when the span runs until the user stops it.
    let endsAt: Date?
}

/// Wording for the keep-awake row. Minute granularity, because a second-by-
/// second countdown on a row people glance at reads as noise.
enum AwakeStatus {
    /// Nil once a timed span has run out, so the row stops claiming the Mac is
    /// awake in the moment between expiry and the timer that clears it.
    static func text(for span: AwakeSpan, now: Date = Date()) -> String? {
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

/// Holds a power assertion for a chosen span. An open-ended assertion is easy
/// to switch on and forget about for days, so the duration is part of the
/// control rather than a separate thing to remember.
final class AwakeController {
    /// Minutes to stay awake. `0` is off; `indefinite` never expires.
    static let indefinite = -1

    private var activity: NSObjectProtocol?
    private var expiry: Timer?
    private var startedAt: Date?
    private(set) var minutes = 0
    private(set) var endsAt: Date?

    /// Fires on the main thread when a timed span runs out, so the UI can
    /// stop claiming the Mac is being kept awake.
    var onExpiry: (() -> Void)?

    var isActive: Bool { activity != nil }

    /// What the row reports while the assertion is held. Nil when off.
    var span: AwakeSpan? {
        guard let startedAt, isActive else { return nil }
        return AwakeSpan(startedAt: startedAt, endsAt: endsAt)
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
            // Changing the span later must not restart the clock: the Mac has
            // been awake since this assertion began, not since the last edit.
            startedAt = Date()
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
        startedAt = nil
    }

    deinit {
        expiry?.invalidate()
        release()
    }
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
