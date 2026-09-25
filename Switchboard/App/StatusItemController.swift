import AppKit
import OSLog
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "welcome")
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = MenuBarPopover()
    private let store = TweakStore()
    private let monitor = SystemMonitor()
    private let shortcuts = GlobalShortcuts(registrar: HotKeyRegistrar())
    private let fileShelf = FileShelfController()
    private let appearance = AppearanceSetting()
    private let shelfDragWatcher = ShelfDragWatcher()
    private let finderEject = FinderEjectShortcut()
    private let snapper = WindowSnapper()
    private let switcher = WindowSwitcher()
    private lazy var dragGrid = WindowDragGrid(snapper: snapper)
    private var shortcutSettings: ShortcutSettingsController?
    private var welcome: WelcomeWindowController?
    private var hostingController: NSHostingController<PopoverView>?
    private var restartProtection = false
    private var restartProtectionGeneration = 0
    private var restartProtectionRelease: DispatchWorkItem?
    /// Only restore the panel if it was actually open when selection started.
    private var selectionWasShowingPopover = false
    private var captureWasStartedByShortcut = false
    private var lastDismissedNoticeID: UUID?

    override init() {
        super.init()
        shortcuts.onAction = { [weak self] action in self?.performShortcut(action) }
        switcher.onBegin = { [weak self] in self?.popover.close() }
        switcher.isRegisteredShortcut = { [weak self] shortcut in self?.shortcuts.isRegistered(shortcut) ?? false }
        switcher.onError = { [weak self] message in
            self?.store.notice = StoreNotice(kind: .error, message: message)
            self?.showPopover(category: .everyday)
        }
        shortcuts.setSwitcherActionsEnabled(store.isWindowSwitchingActive)
        switcher.setEnabled(store.isWindowSwitchingActive)
        store.onWindowSwitchingChange = { [weak self] active in
            guard let self else { return }
            self.switcher.setEnabled(active)
            self.shortcuts.setSwitcherActionsEnabled(active)
            if active, ShortcutAction.allCases.contains(where: { $0.group == .windowSwitcher && self.shortcuts.errors[$0] != nil }) {
                self.store.notice = StoreNotice(kind: .error,
                                                message: "Some switcher shortcuts are unavailable. Review them in Keyboard Shortcuts.")
            }
        }
        shortcuts.setWindowActionsEnabled(store.isWindowSnappingActive)
        setDragGridActive(store.isWindowSnappingActive)
        store.onWindowSnappingChange = { [weak self] active in
            guard let self else { return }
            self.shortcuts.setWindowActionsEnabled(active)
            self.setDragGridActive(active)
            let taken = ShortcutAction.allCases.contains { $0.group == .windows && self.shortcuts.errors[$0] != nil }
            if active, taken {
                self.store.notice = StoreNotice(kind: .error,
                                                message: "Some window shortcuts are in use by another app. Review them in Keyboard Shortcuts.")
            }
        }
        if !shortcuts.errors.isEmpty {
            store.notice = StoreNotice(kind: .error,
                                      message: "Some shortcuts are unavailable. Open Keyboard Shortcuts from the settings gear to review them.")
        }
        item.button?.image = MenuBarIcon.image
        item.button?.toolTip = "Switchboard"
        item.button?.setAccessibilityLabel("Switchboard")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: .leftMouseDown)
        configureShelfDrop()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        store.onScreenSelectionBegan = { [weak self] in
            guard let self else { return }
            self.switcher.cancel()
            guard self.popover.isShown else { return }
            self.selectionWasShowingPopover = true
            // The crosshair is already up, so the panel has to go at once --
            // the usual fade leaves it sitting over the thing being selected.
            self.popover.animates = false
            self.popover.close()
            self.popover.animates = true
        }
        store.onScreenSelectionEnded = { [weak self] in
            guard let self, self.selectionWasShowingPopover || self.captureWasStartedByShortcut else { return }
            self.selectionWasShowingPopover = false
            self.captureWasStartedByShortcut = false
            // Let screencapture finish tearing down its overlay first, or the
            // popover is presented against a screen that is still captured.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, !self.popover.isShown else { return }
                self.showPopover()
            }
        }
    }

    /// Opens the welcome window on the first launch of this copy of the app.
    func showWelcomeIfNewCopy() {
        let copy: AppCopy
        do {
            copy = try AppCopy.current()
        } catch {
            // Without an identity every launch would look new, and showing the
            // welcome each time is worse than skipping it once.
            logger.error("Welcome skipped, app bundle unreadable: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard WelcomeGate().claim(copy) else { return }
        logger.info("Showing welcome for new copy \(copy.id, privacy: .public)")
        let controller = WelcomeWindowController(
            panelShortcut: shortcuts.bindings[.togglePanel],
            openPanel: { [weak self] in self?.showPopover() },
            onClose: { [weak self] in
                // Released on the next turn so the controller outlives its own close callback.
                DispatchQueue.main.async { self?.welcome = nil }
            }
        )
        welcome = controller
        controller.open()
    }

    @objc private func togglePopover() {
        guard !store.isCapturingText else { return }
        if fileShelf.isVisible {
            fileShelf.close()
            return
        }
        if popover.isShown {
            popover.close()
            return
        }
        showPopover()
    }

    private func showPopover(category: Category? = nil) {
        guard !store.isCapturingText, let button = item.button else { return }
        fileShelf.close()
        switcher.cancel()
        if let category { store.category = category }
        store.search = ""
        if popover.isShown {
            popover.contentViewController?.view.window?.makeKey()
            return
        }

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
            rootView: PopoverView(store: store, monitor: monitor,
                                  dismiss: { [weak self] in self?.popover.close() },
                                  applyRestarts: { [weak self] in
                                      self?.applyPendingRestartsKeepingPopoverOpen()
                                  },
                                  showShortcuts: { [weak self] in self?.showShortcutSettings() },
                                  height: height,
                                  showShelf: { [weak self] in self?.showFileShelf() },
                                  appearance: appearance)
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
        // The popover manages activation. Explicitly activating the app over a
        // full-screen Space makes it resign active again and closes this transient popover.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func performShortcut(_ action: ShortcutAction) {
        guard !store.isCapturingText else { return }
        if let mode = action.switcherMode, let binding = shortcuts.bindings[action] {
            switcher.advance(sameAppOnly: mode.sameApp, backwards: mode.backwards, modifiers: binding.modifiers)
            return
        }
        switcher.cancel()
        switch action {
        case .togglePanel:
            togglePopover()
        case .clipboard:
            showPopover(category: .clipboard)
        case .fileShelf:
            if fileShelf.isVisible { fileShelf.close() } else { showFileShelf() }
        case .captureText:
            guard let tweak = store.catalog.first(where: { $0.id == "everyday.region-ocr" }) else { return }
            captureWasStartedByShortcut = true
            shortcutSettings?.window?.orderOut(nil)
            store.perform(tweak)
        case .toggleAwake:
            store.toggleKeepAwake()
            showPopover(category: .everyday)
        default:
            guard let command = action.windowCommand else { return }
            snapFocusedWindow(command)
        }
    }

    private func setDragGridActive(_ active: Bool) {
        guard !dragGrid.setActive(active) else { return }
        store.notice = StoreNotice(kind: .error,
                                   message: "macOS would not let Switchboard watch window drags. Keyboard snapping still works.")
    }

    private func snapFocusedWindow(_ command: WindowCommand) {
        snapper.perform(command) { [weak self] outcome in
            switch outcome {
            case .moved:
                break
            case .nothingToMove:
                NSSound.beep()
            case .needsPermission:
                WindowSnapper.requestPermission()
                self?.store.notice = StoreNotice(kind: .information,
                                                 message: "Allow Switchboard under Accessibility so window shortcuts can move windows.")
                // The toggle turns itself off on refresh, so show the panel
                // where that state and this notice can be seen together.
                self?.showPopover(category: .everyday)
            }
        }
    }

    private func showShortcutSettings() {
        switcher.cancel()
        fileShelf.close()
        popover.close()
        if shortcutSettings == nil {
            shortcutSettings = ShortcutSettingsController(shortcuts: shortcuts)
        }
        shortcutSettings?.open()
    }

    private func configureShelfDrop() {
        shelfDragWatcher.onTrigger = { [weak self] files, pointer in
            guard let self, !self.store.isCapturingText else { return }
            self.switcher.cancel()
            self.popover.close()
            self.fileShelf.show(beside: pointer, incoming: files)
        }
        shelfDragWatcher.onDragEnded = { [weak self] in self?.fileShelf.dragEndedElsewhere() }
        shelfDragWatcher.start()
        // Finder's Command-Delete needs the disk list before the shelf is ever opened;
        // mount notifications keep it current after this.
        fileShelf.volumes.refresh()
        finderEject.ejectable = { [weak self] in self?.fileShelf.volumes.volumes ?? [] }
        finderEject.onEject = { [weak self] targets in
            guard let self else { return }
            for volume in targets {
                self.fileShelf.volumes.eject(volume, failed: { [weak self] in self?.showFileShelf() })
            }
        }
        finderEject.start()
        fileShelf.shelf.onCountChange = { [weak self] count in
            guard let self, let button = self.item.button else { return }
            self.item.length = count == 0 ? NSStatusItem.squareLength : NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.title = count == 0 ? "" : " \(count)"
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.setAccessibilityLabel(count == 0 ? "Switchboard" : "Switchboard, \(count) items on shelf")
            button.toolTip = count == 0 ? "Switchboard" : "Switchboard · \(count) items on shelf"
        }
    }

    private func showFileShelf() {
        guard !store.isCapturingText, let button = item.button else { return }
        switcher.cancel()
        popover.close()
        fileShelf.show(relativeTo: button)
    }

    private func applyPendingRestartsKeepingPopoverOpen() {
        restartProtectionRelease?.cancel()
        restartProtection = true
        restartProtectionGeneration += 1
        let generation = restartProtectionGeneration
        store.applyPendingRestarts()

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

    func popoverDidShow(_ notification: Notification) {
        item.button?.highlight(popover.isShown)
    }

    func popoverWillClose(_ notification: Notification) {
        item.button?.highlight(false)
        restartProtectionRelease?.cancel()
        restartProtectionRelease = nil
        restartProtection = false
        restartProtectionGeneration += 1
    }

    func popoverDidClose(_ notification: Notification) {
        lastDismissedNoticeID = store.notice?.id
        // SwiftUI's onDisappear is not guaranteed once the hosting view goes
        // away with the popover, and a missed one would leave the audio list
        // polling against a closed panel.
        store.setAudioListVisible(false)
        monitor.stop()
    }
}
