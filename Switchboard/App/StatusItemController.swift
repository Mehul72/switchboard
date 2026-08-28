import AppKit

final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        item.button?.image = MenuBarIcon.image
        item.button?.target = self
        item.button?.action = #selector(toggle)
    }

    @objc private func toggle() {
        NSSound.beep()
    }
}
