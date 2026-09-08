import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        let source = NSImage(resource: .brandMark)
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.addRepresentations(source.representations)
        image.isTemplate = true
        image.accessibilityDescription = "Switchboard"
        return image
    }()
}
