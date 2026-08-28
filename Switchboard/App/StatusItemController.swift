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
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        // Rebuilt on every open so the rows start from freshly read values and
        // the search field takes focus again.
        store.refresh()
        store.search = ""
        let controller = NSHostingController(
            rootView: PopoverView(store: store, dismiss: { [weak self] in
                self?.popover.performClose(nil)
            })
        )
        controller.view.layoutSubtreeIfNeeded()
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The hosting window starts behind whatever was frontmost, which eats
        // the first click on a toggle.
        popover.contentViewController?.view.window?.makeKey()
    }
}
