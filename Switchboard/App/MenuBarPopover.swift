import AppKit
import OSLog

@MainActor
final class MenuBarPopover: NSPopover {
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "menu-panel")
    private weak var anchor: NSView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appearanceObserver: NSKeyValueObservation?

    override init() {
        super.init()
        behavior = .transient
        appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateAppearance() }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSPopover.willCloseNotification,
                                                                object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopMonitoring() }
        }
    }

    required init?(coder: NSCoder) { fatalError("MenuBarPopover is created programmatically") }

    override func show(relativeTo positioningRect: NSRect, of positioningView: NSView, preferredEdge: NSRectEdge) {
        anchor = positioningView
        updateAppearance()
        super.show(relativeTo: positioningRect, of: positioningView, preferredEdge: preferredEdge)
        if isShown { startMonitoring() }
    }

    private func updateAppearance() {
        let resolved = NSApplication.shared.effectiveAppearance
        appearance = resolved
        // AppKit updates the popover chrome but can leave NSHostingView with its
        // original inherited appearance. Set the content too, including Match System changes.
        contentViewController?.view.appearance = resolved
    }

    private func startMonitoring() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            // Explicit dismissal must bypass the delegate's temporary Finder/Dock restart protection.
            self?.close()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self, self.isShown else { return event }
            if self.contains(event) { return event }
            self.close()
            return event
        }
        if globalMonitor == nil || localMonitor == nil {
            logger.error("Could not install all outside-click monitors; native popover dismissal remains active")
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            self?.close()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                       object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            // Activation can come from restarting Finder; unlike a click, it may be protected.
            self?.performClose(nil)
        })
    }

    private func contains(_ event: NSEvent) -> Bool {
        if let anchor, event.window === anchor.window,
           anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
            return true
        }
        // Native menus track in their own windows, outside the popover's parent chain.
        if event.window?.level == .popUpMenu { return true }
        let contentWindow = contentViewController?.view.window
        var window = event.window
        while let candidate = window {
            if candidate === contentWindow { return true }
            window = candidate.parent
        }
        return false
    }

    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
