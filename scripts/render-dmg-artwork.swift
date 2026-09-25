import AppKit

// Finder uses point coordinates. Export both scales so the artwork stays sharp on Retina displays.
let canvas = NSSize(width: 800, height: 540)
let ink = NSColor(srgbRed: 0.92, green: 0.93, blue: 0.92, alpha: 1)
let muted = NSColor(srgbRed: 0.56, green: 0.59, blue: 0.60, alpha: 1)
let teal = NSColor(srgbRed: 0.36, green: 0.83, blue: 0.76, alpha: 1)

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
          weight: NSFont.Weight = .regular, color: NSColor = ink, tracking: CGFloat = 0) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .kern: tracking
    ])
}

func line(_ points: [NSPoint], color: NSColor, width: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
}

func mono(_ value: String, x: CGFloat, y: CGFloat, color: NSColor = muted) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: color, .kern: 1.2
    ])
}

func drawArtwork() {
    NSColor(srgbRed: 0.065, green: 0.071, blue: 0.077, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvas).fill()
    let rule = NSColor(srgbRed: 0.19, green: 0.21, blue: 0.22, alpha: 1)

    roundedRect(NSRect(x: 48, y: 39, width: 6, height: 6), radius: 1, fill: teal)
    mono("SWITCHBOARD / INSTALL", x: 65, y: 36)
    mono("FOR macOS", x: 679, y: 36)
    line([NSPoint(x: 48, y: 66), NSPoint(x: 752, y: 66)], color: rule)

    text("Switchboard", x: 44, y: 93, size: 62, weight: .medium, tracking: -2.8)
    text("Drag the app into Applications to install.", x: 48, y: 175, size: 15, color: muted)

    // The terminal dots and continuous trace are the same geometry as the menu bar mark.
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 732, y: 112))
    mark.line(to: NSPoint(x: 689, y: 112))
    mark.curve(to: NSPoint(x: 689, y: 144), controlPoint1: NSPoint(x: 665, y: 112),
               controlPoint2: NSPoint(x: 665, y: 144))
    mark.line(to: NSPoint(x: 714, y: 144))
    mark.curve(to: NSPoint(x: 714, y: 176), controlPoint1: NSPoint(x: 738, y: 144),
               controlPoint2: NSPoint(x: 738, y: 176))
    mark.line(to: NSPoint(x: 671, y: 176))
    mark.lineWidth = 2
    mark.lineCapStyle = .round
    teal.withAlphaComponent(0.75).setStroke()
    mark.stroke()
    teal.setFill()
    for point in [NSPoint(x: 732, y: 112), NSPoint(x: 671, y: 176)] {
        NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
    }

    mono("01", x: 140, y: 247, color: teal)
    mono("THE APP", x: 168, y: 247)
    mono("02", x: 500, y: 247, color: teal)
    mono("APPLICATIONS", x: 528, y: 247)
    for center in [CGFloat(220), CGFloat(580)] {
        // Open corners frame the real Finder icons without suggesting clickable controls.
        for side in [CGFloat(-1), CGFloat(1)] {
            let edge = center + side * 87
            line([NSPoint(x: edge - side * 16, y: 279), NSPoint(x: edge, y: 279),
                  NSPoint(x: edge, y: 295)], color: rule)
            line([NSPoint(x: edge, y: 372), NSPoint(x: edge, y: 388),
                  NSPoint(x: edge - side * 16, y: 388)], color: rule)
        }
        // Finder forces black filenames over custom pictures, even in Dark Mode.
        // A small metal nameplate keeps the native selectable labels readable in both appearances.
        roundedRect(NSRect(x: center - 70, y: 398, width: 140, height: 23), radius: 2,
                    fill: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.60, alpha: 1))
    }

    line([NSPoint(x: 334, y: 336), NSPoint(x: 466, y: 336)], color: rule)
    line([NSPoint(x: 379, y: 336), NSPoint(x: 422, y: 336)], color: teal, width: 1.5)
    line([NSPoint(x: 415, y: 329), NSPoint(x: 422, y: 336), NSPoint(x: 415, y: 343)],
         color: teal, width: 1.5)
    mono("DRAG & DROP", x: 360, y: 365)

    line([NSPoint(x: 48, y: 464), NSPoint(x: 752, y: 464)], color: rule)
    text("Once copied, open Switchboard from Applications.", x: 48, y: 485, size: 13, color: muted)
    mono("EJECT WHEN DONE", x: 639, y: 487)
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: render-dmg-artwork <output-directory>\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for scale in [1, 2] {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.width) * scale,
            pixelsHigh: Int(canvas.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "DMGArtwork", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap"])
        }
        bitmap.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        graphics.cgContext.translateBy(x: 0, y: canvas.height)
        graphics.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: graphics.cgContext, flipped: true)
        drawArtwork()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DMGArtwork", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot encode PNG"])
        }
        try png.write(to: output.appendingPathComponent(scale == 1 ? "background.png" : "background@2x.png"))
    }
} catch {
    fputs("Artwork failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
