import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        // Control Center already occupies the switch-and-slider look a few
        // icons away, so anything in that family reads as a duplicate. Routing
        // points are the older meaning of a switchboard and share no silhouette
        // with it.
        let symbol = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                             accessibilityDescription: "Switchboard")!
        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ) ?? symbol
        configured.isTemplate = true
        return configured
    }()
}
