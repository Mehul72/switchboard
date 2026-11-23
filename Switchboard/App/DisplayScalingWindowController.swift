import AppKit
import Combine
import SwiftUI

@MainActor
final class DisplayScalingWindowController: NSWindowController, NSWindowDelegate {
    private let scaling: DisplayScalingController
    private var observations: Set<AnyCancellable> = []

    init(controller: DisplayScalingController, appearance: AppearanceSetting) {
        scaling = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Display Scaling"
        window.minSize = NSSize(width: 480, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = NSHostingView(rootView: DisplayScalingView(controller: controller) { [weak window] in
            window?.performClose(nil)
        })
        content.sizingOptions = []
        content.frame = window.contentLayoutRect
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        window.center()

        appearance.$choice.sink { [weak window] choice in
            window?.appearance = choice.appearance
        }.store(in: &observations)
        controller.$errorMessage.removeDuplicates().compactMap { $0 }.sink { [weak self] message in
            self?.announce(message)
        }.store(in: &observations)
        controller.$confirmationSeconds.map { $0 != nil }.removeDuplicates().sink { [weak self] pending in
            guard pending else { return }
            // Display changes can leave the confirmation controls outside the new desktop.
            DispatchQueue.main.async {
                guard let self, self.scaling.confirmationSeconds != nil,
                      self.window?.isVisible == true else { return }
                self.keepWindowOnScreen()
                self.window?.makeKeyAndOrderFront(nil)
                self.announce("Keep this text size? It will revert automatically in twenty seconds. Press Return to keep it, or Escape to revert.")
            }
        }.store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.keepWindowOnScreen() }
            }.store(in: &observations)
    }

    required init?(coder: NSCoder) { nil }

    func open() {
        scaling.refresh()
        keepWindowOnScreen()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        scaling.windowWillClose()
    }

    private func keepWindowOnScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    private func announce(_ message: String) {
        guard let window, window.isVisible else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
