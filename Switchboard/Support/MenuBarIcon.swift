import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        let symbol = NSImage(systemSymbolName: "switch.2",
                             accessibilityDescription: "Switchboard")!
        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ) ?? symbol
        configured.isTemplate = true
        return configured
    }()
}
