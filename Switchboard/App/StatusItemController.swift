import AppKit
import SwiftUI

final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let store = TweakStore()
    private var hostingController: NSHostingController<PopoverView>?
    private var restartProtection = false
    private var restartProtectionGeneration = 0
    private var restartProtectionRelease: DispatchWorkItem?
    /// Only restore the panel if it was actually open when selection started.
    private var selectionWasShowingPopover = false
    private var lastDismissedNoticeID: UUID?

    override init() {
        super.init()
        item.button?.image = MenuBarIcon.image
        item.button?.toolTip = "Switchboard"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        store.onScreenSelectionBegan = { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.selectionWasShowingPopover = true
            // The crosshair is already up, so the panel has to go at once --
            // the usual fade leaves it sitting over the thing being selected.
            self.popover.animates = false
            self.popover.performClose(nil)
            self.popover.animates = true
        }
        store.onScreenSelectionEnded = { [weak self] in
            guard let self, self.selectionWasShowingPopover else { return }
            self.selectionWasShowingPopover = false
            // Let screencapture finish tearing down its overlay first, or the
            // popover is presented against a screen that is still captured.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, !self.popover.isShown else { return }
                self.togglePopover()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        store.search = ""
        if let notice = store.notice,
           notice.kind != .error,
           notice.id == lastDismissedNoticeID {
            store.notice = nil
        }
        store.refresh()

        let screen = button.window?.screen ?? NSScreen.main
        let availableHeight = max(320, (screen?.visibleFrame.height ?? Theme.popoverHeight) - 16)
        let height = min(Theme.popoverHeight, availableHeight)
        let size = NSSize(width: Theme.popoverWidth, height: height)
        let controller = NSHostingController(
            rootView: PopoverView(store: store,
                                  dismiss: { [weak self] in self?.popover.performClose(nil) },
                                  applyRestarts: { [weak self] in
                                      self?.applyPendingRestartsKeepingPopoverOpen()
                                  },
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

    private func applyPendingRestartsKeepingPopoverOpen() {
        restartProtectionRelease?.cancel()
        restartProtection = true
        restartProtectionGeneration += 1
        let generation = restartProtectionGeneration
        store.applyPendingRestarts()

        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()

        let release = DispatchWorkItem { [weak self] in
            guard let self,
                  self.restartProtectionGeneration == generation else { return }
            self.restartProtection = false
            self.restartProtectionRelease = nil
        }
        restartProtectionRelease = release
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: release)
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        !restartProtection
    }

    func popoverDidClose(_ notification: Notification) {
        lastDismissedNoticeID = store.notice?.id
    }
}
