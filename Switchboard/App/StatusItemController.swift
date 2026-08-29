import AppKit
import SwiftUI

final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store = TweakStore()
    private var hostingController: NSHostingController<PopoverView>?

    init() {
        item.button?.image = MenuBarIcon.image
        item.button?.toolTip = "Switchboard"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        store.refresh()
        store.search = ""
        store.notice = nil

        let screen = button.window?.screen ?? NSScreen.main
        let availableHeight = max(320, (screen?.visibleFrame.height ?? Theme.popoverHeight) - 16)
        let height = min(Theme.popoverHeight, availableHeight)
        let size = NSSize(width: Theme.popoverWidth, height: height)
        let controller = NSHostingController(
            rootView: PopoverView(store: store,
                                  dismiss: { [weak self] in self?.popover.performClose(nil) },
                                  height: height)
        )

        // Dynamic SwiftUI resizing after presentation can move a status-item
        // popover behind the menu bar, so AppKit owns one stable outer size.
        controller.sizingOptions = []
        controller.preferredContentSize = size
        controller.view.frame.size = size
        hostingController = controller
        popover.contentViewController = controller
        popover.contentSize = size

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}
