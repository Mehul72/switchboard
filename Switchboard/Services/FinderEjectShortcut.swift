import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// Reads what is selected in Finder through Accessibility. Covers Finder
/// windows (rows or icons) and the desktop, which is not one of its windows.
enum FinderSelection {
    /// Finder can be busy; a key press must not wait on it for long.
    private static let messagingTimeoutSeconds: Float = 0.3
    /// The selected row keeps its URL on the name field one or two levels down.
    private static let urlSearchDepth = 3

    static func selectedURLs() -> [URL] {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return []
        }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, messagingTimeoutSeconds)
        var items: [AXUIElement] = []
        if let focused: AXUIElement = value(of: app, kAXFocusedUIElementAttribute) {
            items = selection(around: focused)
        }
        // With no Finder window focused the desktop is the target. With one
        // focused, an old desktop selection must not be acted on.
        if items.isEmpty, value(of: app, kAXFocusedWindowAttribute) as AXUIElement? == nil {
            let desktop = children(of: app).first { value(of: $0, kAXRoleAttribute) == kAXScrollAreaRole as String }
            items = desktop.map(selection(around:)) ?? []
        }
        return items.compactMap { fileURL(in: $0, depth: 0) }
    }

    private static func selection(around element: AXUIElement) -> [AXUIElement] {
        for candidate in [element] + children(of: element) {
            for key in [kAXSelectedRowsAttribute, kAXSelectedChildrenAttribute] {
                if let selected: [AXUIElement] = value(of: candidate, key), !selected.isEmpty { return selected }
            }
        }
        return []
    }

    private static func fileURL(in element: AXUIElement, depth: Int) -> URL? {
        if let reference: NSURL = value(of: element, kAXURLAttribute) {
            // Finder hands out file reference URLs (/.file/id=…); the path form is what volumes match.
            return reference.filePathURL
        }
        guard depth < urlSearchDepth else { return nil }
        return children(of: element).lazy.compactMap { fileURL(in: $0, depth: depth + 1) }.first
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: element, kAXChildrenAttribute) ?? []
    }

    private static func value<T>(of element: AXUIElement, _ attribute: String) -> T? {
        var result: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result as? T
    }
}

/// Command-Delete on disks selected in Finder ejects them. Finder ejects with
/// Command-E and ignores Command-Delete on a disk, so nothing is taken away;
/// files and mixed selections are left for Finder to move to the Trash.
@MainActor
final class FinderEjectShortcut {
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "shelf-volumes")
    private let selectionQueue = DispatchQueue(label: "com.Mehul72.switchboard.finder-selection", qos: .userInitiated)
    private var monitor: Any?

    /// Receives the disks to eject. Only called when every selected item is one.
    var onEject: ([ShelfVolume]) -> Void = { _ in }
    /// The disks that may be ejected right now.
    var ejectable: () -> [ShelfVolume] = { [] }

    nonisolated static func isCommandDelete(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == UInt16(kVK_Delete) && modifiers.intersection([.command, .shift, .option, .control]) == .command
    }

    /// Everything selected must be an ejectable disk. One file in the mix means
    /// the user is trashing things, which is Finder's job, not an eject.
    nonisolated static func volumesToEject(selected: [URL], ejectable: [ShelfVolume]) -> [ShelfVolume] {
        var targets: [ShelfVolume] = []
        for url in selected {
            let path = url.standardizedFileURL.path
            guard let volume = ejectable.first(where: { $0.url.standardizedFileURL.path == path }) else { return [] }
            // Volumes of one disk image go together, so a second eject would only fail.
            let sameImage = volume.imageDevice != nil && targets.contains { $0.imageDevice == volume.imageDevice }
            if !targets.contains(volume), !sameImage { targets.append(volume) }
        }
        return targets
    }

    /// Global key monitors only deliver events once Accessibility is granted;
    /// until then this stays installed and silent. Only the key code and
    /// modifiers of each press are read, and nothing is kept.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isCommandDelete(keyCode: event.keyCode, modifiers: event.modifierFlags),
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else { return }
            MainActor.assumeIsolated { self?.commandDeleteInFinder() }
        }
        if monitor == nil { logger.error("Finder eject key monitor refused") }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func commandDeleteInFinder() {
        selectionQueue.async { [weak self] in
            let selected = FinderSelection.selectedURLs()
            DispatchQueue.main.async {
                guard let self else { return }
                let targets = Self.volumesToEject(selected: selected, ejectable: self.ejectable())
                guard !targets.isEmpty else { return }
                self.onEject(targets)
            }
        }
    }
}
