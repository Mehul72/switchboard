import AppKit
import Darwin
import SwiftUI

@main
enum ShelfVisualCheck {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                if CommandLine.arguments.contains("--disk") {
                    try await Task.detached { try checkDisposableDisk() }.value
                } else {
                    try await renderExamples()
                }
                exit(0)
            } catch {
                fputs("Shelf rendering failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    private static func checkDisposableDisk() throws {
        // Finder formats new images as APFS, whose volume sits on a synthesized
        // container disk; HFS+ does not, so both layouts need an eject check.
        for fileSystem in ["HFS+", "APFS"] { try checkDisposableDisk(fileSystem: fileSystem) }
    }

    private static func checkDisposableDisk(fileSystem: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Switchboard-Shelf-Check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = directory.appendingPathComponent("Test image ' $.dmg")
        let mountPoint = directory.appendingPathComponent("Mounted")
        do {
            _ = try diskCommand(["create", "-size", "20m", "-fs", fileSystem, "-volname", "Shelf test", image.path])
            _ = try diskCommand(["attach", "-noautoopen", "-mountpoint", mountPoint.path, "-plist", image.path])
            let listed = try NativeShelfVolumes.linkingImages(NativeShelfVolumes.list())
            guard let volume = listed.first(where: { $0.url.path == mountPoint.path }) else {
                throw checkError("\(fileSystem): the disposable mounted image was not discovered.")
            }
            guard volume.imageURL?.resolvingSymlinksInPath() == image.resolvingSymlinksInPath() else {
                throw checkError("\(fileSystem): the mounted image was not associated with its source file.")
            }
            print("PASS: \(fileSystem) image is discovered and associated")
            try NativeShelfVolumes.eject(volume)
            guard try !NativeShelfVolumes.list().contains(where: { $0.id == volume.id }) else {
                throw checkError("\(fileSystem): the disposable volume is still mounted after eject.")
            }
            guard try attachedDevice(of: image) == nil else {
                throw checkError("\(fileSystem): the volume unmounted but the image is still attached, so opening it again does nothing.")
            }
            guard FileManager.default.fileExists(atPath: image.path) else {
                throw checkError("\(fileSystem): the source image was removed during eject.")
            }
            print("PASS: \(fileSystem) eject detaches the image and preserves its source file")
            try FileManager.default.removeItem(at: directory)
        } catch {
            if let device = try? attachedDevice(of: image) {
                do { _ = try diskCommand(["detach", device]) }
                catch { throw checkError("Fixture cleanup failed. Detach \(device) for \(image.path): \(error)") }
            }
            try FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func attachedDevice(of image: URL) throws -> String? {
        let info = try diskCommand(["info", "-plist"])
        let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
        let images = plist?["images"] as? [[String: Any]] ?? []
        let target = image.resolvingSymlinksInPath().path
        let match = images.first { ($0["image-path"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == target }
        let entities = match?["system-entities"] as? [[String: Any]]
        return entities?.first?["dev-entry"] as? String
    }

    private static func diskCommand(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationStatus == 0 else { throw checkError("Disk fixture command failed: \(arguments[0])") }
        return data
    }

    private static func checkError(_ message: String) -> NSError {
        NSError(domain: "Switchboard.ShelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    @MainActor
    private static func renderExamples() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("build/shelf-preview")
        let samples = output.appendingPathComponent("Sample files")
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let text = samples.appendingPathComponent("Release notes.md")
        let picture = samples.appendingPathComponent("Workspace.png")
        let folder = samples.appendingPathComponent("Design assets")
        try Data("# Switchboard\n\nA place for the files you are working with.\n".utf8).write(to: text)
        if !FileManager.default.fileExists(atPath: picture.path) {
            try FileManager.default.copyItem(at: root.appendingPathComponent("docs/images/overview.png"), to: picture)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mounted = [
            ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "example-drive"),
            ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Switchboard"), name: "Switchboard", uuid: "example-image",
                        imageURL: samples.appendingPathComponent("Switchboard.dmg"))
        ]

        // A nil height sizes the panel to its content, as the app does.
        for (name, dark, empty, incoming, height) in [
            ("light", false, false, [URL](), CGFloat?.none),
            ("dark", true, false, [], nil),
            ("empty", false, true, [], nil),
            ("eject", true, false, [mounted[0].url], nil),
            ("disk-image", false, false, [samples.appendingPathComponent("Switchboard.dmg")], nil),
            ("short", true, false, [], 200)
        ] {
            let shelf = FileShelf()
            if !empty { shelf.add([picture, text, folder]) }
            shelf.notice = nil
            let volumes = ShelfVolumes(load: { $0(.success(empty ? [] : mounted)) }, eject: { _, _ in
                preconditionFailure("Visual examples must never eject disks")
            })
            volumes.refresh()
            let drag = ShelfDragState()
            if !incoming.isEmpty { drag.enter(incoming) }
            let view = FileShelfView(shelf: shelf, volumes: volumes, drag: drag, addFiles: {}, close: {})
                .preferredColorScheme(dark ? .dark : .light)
            let panel = NSPanel(contentRect: NSRect(x: 40, y: 40, width: FileShelfController.width, height: 400),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            let host = NSHostingView(rootView: view)
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            host.layoutSubtreeIfNeeded()
            panel.setContentSize(NSSize(width: FileShelfController.width,
                                        height: height ?? min(host.fittingSize.height.rounded(.up), FileShelfController.maximumHeight)))
            panel.orderFrontRegardless()
            // Let native hosting views and Quick Look finish their first display pass.
            try await Task.sleep(for: .milliseconds(600))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: output.appendingPathComponent("\(name).png"))
            panel.orderOut(nil)
            print("Rendered \(name): \(Int(host.bounds.width)) × \(Int(host.bounds.height))")
        }
        print("Shelf examples saved to \(output.path)")
    }
}
