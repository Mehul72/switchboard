import AppKit
import Combine
import SwiftUI

@MainActor
final class FileShelfController: NSObject, NSWindowDelegate {
    nonisolated static let width: CGFloat = 296
    /// Taller content scrolls instead of covering the screen.
    static let maximumHeight: CGFloat = 560
    let shelf: FileShelf
    let volumes: ShelfVolumes
    let drag = ShelfDragState()
    private(set) var panel: NSPanel?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []
    private var choosingFiles = false
    private var announcedNotice: String?

    convenience override init() {
        self.init(shelf: FileShelf(), volumes: ShelfVolumes())
    }

    init(shelf: FileShelf, volumes: ShelfVolumes) {
        self.shelf = shelf
        self.volumes = volumes
        super.init()
        shelf.$notice.combineLatest(volumes.$notice).sink { [weak self] fileNotice, volumeNotice in
            self?.announce(ShelfNotice.latest(volumeNotice, fileNotice))
        }.store(in: &subscriptions)
        // Published values change before SwiftUI lays out, so resize on the next turn.
        Publishers.Merge3(shelf.objectWillChange, volumes.objectWillChange, drag.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.fitToContent() }
            .store(in: &subscriptions)
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(relativeTo button: NSStatusBarButton) {
        guard let anchorWindow = button.window else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        present(on: anchorWindow.screen ?? NSScreen.main) { visible, height in
            NSPoint(x: max(visible.minX + 8, min(anchor.maxX - Self.width, visible.maxX - Self.width - 8)),
                    y: max(visible.minY + 8, anchor.minY - height - 8))
        }
        panel?.makeKey()
    }

    /// Opens beside the pointer mid-drag. The pointer stays outside the panel
    /// so releasing without moving never lands on an eject target.
    func show(beside pointer: NSPoint, incoming: [URL]) {
        drag.enter(incoming)
        guard !isVisible else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        present(on: screen) { visible, height in
            Self.origin(beside: pointer, height: height, in: visible)
        }
    }

    nonisolated static func origin(beside pointer: NSPoint, height: CGFloat, in visible: NSRect) -> NSPoint {
        let gap: CGFloat = 12
        let fitsRight = pointer.x + gap + width <= visible.maxX - 8
        let x = fitsRight ? pointer.x + gap : pointer.x - gap - width
        // Line the drop targets under the header up with the pointer.
        let y = pointer.y + 76 - height
        return NSPoint(x: max(visible.minX + 8, min(x, visible.maxX - width - 8)),
                       y: max(visible.minY + 8, min(y, visible.maxY - height - 8)))
    }

    private func present(on screen: NSScreen?, origin: (NSRect, CGFloat) -> NSPoint) {
        shelf.refresh()
        volumes.refresh()
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        if !isVisible { createPanel() }
        guard let panel else { return }
        let height = fittedHeight(in: visible)
        panel.setFrame(NSRect(origin: origin(visible, height), size: NSSize(width: Self.width, height: height)),
                       display: true)
        panel.orderFrontRegardless()
        installDismissalMonitors()
    }

    private func fittedHeight(in visible: NSRect) -> CGFloat {
        guard let host = panel?.contentView else { return Self.maximumHeight }
        host.layoutSubtreeIfNeeded()
        return max(120, min(host.fittingSize.height.rounded(.up), Self.maximumHeight, visible.height - 16))
    }

    /// Grows or shrinks with the shelf while keeping the top edge still, so
    /// targets under the pointer do not jump during a drag.
    private func fitToContent() {
        guard isVisible, let panel else { return }
        let visible = panel.screen?.visibleFrame ?? panel.frame
        let height = fittedHeight(in: visible)
        guard abs(height - panel.frame.height) >= 1 else { return }
        let top = min(panel.frame.maxY, visible.maxY)
        let y = max(visible.minY + 8, top - height)
        panel.setFrame(NSRect(x: panel.frame.minX, y: y, width: Self.width, height: height), display: true)
    }

    /// A drag that ended outside the panel never reaches its drop handlers.
    /// The delay lets a drop that did land finish before the targets change.
    func dragEndedElsewhere() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
            self.drag.finish()
        }
    }

    func close() {
        panel?.orderOut(nil)
        drag.finish()
        removeDismissalMonitors()
    }

    @discardableResult
    func accept(_ urls: [URL]) -> Bool {
        let drop = ShelfDrop(urls: urls, volumes: volumes.volumes)
        volumes.notice = nil
        let added = shelf.add(drop.files)
        if !drop.volumes.isEmpty {
            shelf.notice = ShelfNotice(text: added ? "Files added. Use Eject for the disks below." : "Drop a disk on the Eject target, or use its eject button.")
        }
        drag.finish()
        panel?.makeKey()
        return added
    }

    func chooseFiles() {
        guard let panel, !choosingFiles else { return }
        let picker = NSOpenPanel()
        picker.title = "Add to Shelf"
        picker.prompt = "Add to Shelf"
        picker.canChooseDirectories = true
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = true
        choosingFiles = true
        picker.beginSheetModal(for: panel) { [weak self] result in
            guard let self else { return }
            self.choosingFiles = false
            if result == .OK { self.accept(picker.urls) }
        }
    }

    private func createPanel() {
        let panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.maximumHeight),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Switchboard Shelf"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        let view = FileShelfView(shelf: shelf, volumes: volumes, drag: drag,
                                 addFiles: { [weak self] in self?.chooseFiles() },
                                 close: { [weak self] in self?.close() })
        let host = ShelfDropHostingView(rootView: view)
        // Reports the natural height used to fit the panel; the panel frame is still set by hand.
        host.sizingOptions = [.intrinsicContentSize]
        host.onHover = { [weak self] urls in self?.drag.enter(urls) }
        host.onDrop = { [weak self] urls in self?.accept(urls) ?? false }
        host.onExit = { [weak self] in self?.drag.isTargeted = false }
        host.onEnd = { [weak self] in self?.drag.finish() }
        panel.contentView = host
        self.panel = panel
    }

    private func installDismissalMonitors() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.choosingFiles, !self.drag.isDraggingOut else { return }
            self.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if !self.choosingFiles, !self.drag.isDraggingOut, event.window != self.panel {
                self.close()
            }
            return event
        }
    }

    private func removeDismissalMonitors() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        outsideMonitor = nil
        localMonitor = nil
    }

    private func announce(_ notice: ShelfNotice?) {
        guard isVisible, let text = notice?.text, text != announcedNotice, let panel else { return }
        announcedNotice = text
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    deinit {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

private final class ShelfPanel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}
