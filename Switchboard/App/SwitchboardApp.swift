import AppKit

@main
enum SwitchboardApp {
    static func main() {
        let app = NSApplication.shared
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
    }
}
