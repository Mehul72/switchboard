import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        // Anything switch-shaped reads as Control Center, which already sits a
        // few icons away in the same menu bar. A wrench shares no silhouette
        // with it and matches what the app is for.
        let symbol = NSImage(systemSymbolName: "wrench.adjustable",
                             accessibilityDescription: "Switchboard")!
        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ) ?? symbol
        configured.isTemplate = true
        return configured
    }()
}
