import AppKit

// Drawn in code rather than shipped as a PNG so it stays crisp at any menu bar
// height and picks up tinting for free as a template image.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let dot: CGFloat = 3.4
            let gap: CGFloat = 2.6
            let span = dot * 3 + gap * 2
            let origin = (size.width - span) / 2

            NSColor.black.setFill()
            for row in 0..<3 {
                for column in 0..<3 {
                    let rect = NSRect(x: origin + CGFloat(column) * (dot + gap),
                                      y: origin + CGFloat(row) * (dot + gap),
                                      width: dot,
                                      height: dot)
                    NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
