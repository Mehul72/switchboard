import AppKit

/// Window snapping and quit-on-close hit-test the click point from background
/// threads. Over Switchboard's own window macOS answers that in-process, on the
/// probe's thread, and SwiftUI then deadlocks with the main thread. Neither
/// probe wants Switchboard's windows, so those hit tests find nothing.
final class SwitchboardApplication: NSApplication {
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard Thread.isMainThread else { return nil }
        return super.accessibilityHitTest(point)
    }
}

@main
enum SwitchboardApp {
    static func main() {
        PreferenceStore.keepScrollBarsVisible()
        let app = SwitchboardApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController()
        statusItem.showWelcomeIfNewCopy()
    }
}
