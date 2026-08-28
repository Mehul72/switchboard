import AppKit
import SwiftUI

final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store = TweakStore()

    init() {
        item.button?.image = MenuBarIcon.image
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // The hosting window starts behind whatever was frontmost, which
            // eats the first click on a toggle.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
