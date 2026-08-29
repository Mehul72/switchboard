import AppKit
import Foundation

final class AwakeController {
    private var activity: NSObjectProtocol?

    var isActive: Bool { activity != nil }

    func setActive(_ active: Bool) -> Bool {
        if active == isActive { return true }
        if active {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "Switchboard Keep Awake"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        return active == isActive
    }

    deinit {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
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
