import AppKit
import SwiftUI

@main
struct DocumentationRenderer {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await render()
                exit(0)
            } catch {
                fputs("Documentation rendering failed: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    @MainActor
    static func render() async throws {
        let capturePath = ProcessInfo.processInfo.environment["SWITCHBOARD_DOCS_CAPTURES"]
            ?? FileManager.default.currentDirectoryPath + "/build/docs/captures"
        let output = URL(fileURLWithPath: capturePath)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let monitor = SystemMonitor()
        let suite = "Switchboard.Documentation.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.fileReadUnknown) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let store = TweakStore(defaults: defaults, pasteboard: pasteboard)
        let appearance = AppearanceSetting(defaults: defaults)
        // Its own suite, so the renderer never changes the real menu bar readout.
        let readout = MenuBarReadout(defaults: defaults)
        // Never started, so the renderer makes no request to GitHub.
        let updates = UpdateChecker(defaults: defaults)
        let audio = [("com.apple.Music", "Music", "/System/Applications/Music.app", Float(0.35)),
                     ("com.apple.Safari", "Safari", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", Float(0.7)),
                     ("com.apple.FaceTime", "FaceTime", "/System/Applications/FaceTime.app", Float(1))]
        store.audioApps = audio.map { id, name, path, _ in
            AudioApp(bundleID: id, name: name, icon: NSWorkspace.shared.icon(forFile: path),
                     processObjectIDs: [], isPlaying: true)
        }
        store.audioVolumes = Dictionary(uniqueKeysWithValues: audio.map { ($0.0, $0.3) })
        store.audioOutputDevices = [AudioOutputDevice(uid: "speakers", name: "MacBook Speakers"),
                                    AudioOutputDevice(uid: "headphones", name: "Studio Headphones")]
        store.systemDefaultOutputUID = "speakers"
        store.audioRoutes = ["com.apple.Music": "headphones"]
        store.clips = ["The meeting has moved to 10:30.",
                       "Weekend jobs\nBack up the laptop\nSort the holiday photos\nBook the bike service",
                       "https://github.com/Mehul72/switchboard"].map {
            ClipEntry(text: $0, imageData: nil, pixelSize: nil, date: Date(), note: nil)
        }
        monitor.reading = SystemReading(cpu: 18, gpu: 9, memoryUsed: 8.4e9, memoryTotal: 24e9,
                                        swapUsed: 0.2e9, network: NetworkRate(received: 1.2e6, sent: 128e3),
                                        diskFree: 320e9, diskTotal: 500e9,
                                        power: PowerReading(state: "External power"))
        let safari = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        let music = "/System/Applications/Music.app"
        let processes = [
            ProcessUsage(id: safari, name: "Safari", bundlePath: safari, processIDs: Array(101...108), cpu: 6.2,
                         memoryBytes: 2.1e9, isOwnedByUser: true),
            ProcessUsage(id: "pid:201", name: "mds_stores", bundlePath: nil, processIDs: [201], cpu: 3.4,
                         memoryBytes: 0.2e9, isOwnedByUser: false),
            ProcessUsage(id: music, name: "Music", bundlePath: music, processIDs: [301], cpu: 1.8,
                         memoryBytes: 0.4e9, isOwnedByUser: true),
            ProcessUsage(id: "pid:401", name: "WindowServer", bundlePath: nil, processIDs: [401], cpu: 1.2,
                         memoryBytes: 0.6e9, isOwnedByUser: false)
        ]
        monitor.reading.processes = TopProcesses(byCPU: processes,
                                                 byMemory: processes.sorted { $0.memoryBytes > $1.memoryBytes },
                                                 cpuMeasured: true)
        monitor.history = (0..<30).map { index in
            var reading = monitor.reading
            reading.date = Date().addingTimeInterval(Double(index - 30) * 2)
            reading.cpu = 18 + sin(Double(index) * 0.6) * 8
            reading.gpu = 9 + cos(Double(index) * 0.4) * 5
            return reading
        }
        for (name, category, dark) in [("everyday-light", Category.everyday, false),
                                        ("everyday-dark", .everyday, true), ("audio-dark", .audio, true),
                                        ("clipboard-light", .clipboard, false), ("system-dark", .system, true)] {
            appearance.choice = dark ? .dark : .light
            store.category = category
            monitor.reading.date = Date()
            let captureHeight: CGFloat = category == .system ? 660 : 680
            let view = PopoverView(store: store, monitor: monitor, readout: readout, dismiss: {}, applyRestarts: {},
                                   showShortcuts: {}, height: captureHeight, appearance: appearance,
                                   updates: updates)
                .preferredColorScheme(dark ? .dark : .light)
            try await capture(view, name: name, size: NSSize(width: 440, height: captureHeight), dark: dark, output: output)
        }
        try await renderSystem(monitor: monitor, readout: readout, output: output)
        try await renderFeatures(store: store, appearance: appearance, output: output)
        try await renderWindowTools(output: output)
    }

    @MainActor
    static func renderSystem(monitor: SystemMonitor, readout: MenuBarReadout, output: URL) async throws {
        for (name, sort, showReadings) in [("system-cpu", ProcessSort.cpu, false),
                                         ("system-memory", .memory, false),
                                         ("system-readouts", .memory, true)] {
            readout.setShown(.cpu, showReadings)
            readout.setShown(.memory, showReadings)
            let system = SystemMonitorView(monitor: monitor, readout: readout, processSort: sort)
            let view = VStack(alignment: .leading, spacing: 14) {
                Text("System").font(.sectionHeader).foregroundStyle(Theme.primary)
                system.processPanel
                system.readoutPanel
                if showReadings {
                    Text("Menu bar reading example").font(.rowSubtitle).foregroundStyle(Theme.secondary)
                    Text(ReadoutFormat.text(for: monitor.reading, metrics: readout.metrics))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.primary)
                        .padding(10)
                        .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(Theme.edgeInset)
            .frame(width: 440)
            .background(PopoverBackground())
            .preferredColorScheme(.dark)
            try await capture(view, name: name, size: NSSize(width: 440, height: 520),
                              dark: true, output: output, naturalHeight: true)
        }
    }

    @MainActor
    static func capture<V: View>(_ view: V, name: String, size: NSSize, dark: Bool, output: URL, naturalHeight: Bool = false) async throws {
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = naturalHeight ? [.intrinsicContentSize] : []
        panel.contentView = host
        panel.setContentSize(size)
        if naturalHeight {
            host.layoutSubtreeIfNeeded()
            panel.setContentSize(NSSize(width: size.width, height: host.fittingSize.height.rounded(.up)))
        }
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap: NSBitmapImageRep
        if let rawScale = ProcessInfo.processInfo.environment["SWITCHBOARD_DOCS_CAPTURE_SCALE"] {
            guard let scale = Int(rawScale), (1...4).contains(scale) else {
                throw NSError(domain: "Switchboard.Documentation", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Capture scale must be an integer from 1 to 4"])
            }
            guard let scaled = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: Int((host.bounds.width * CGFloat(scale)).rounded(.up)),
                                                pixelsHigh: Int((host.bounds.height * CGFloat(scale)).rounded(.up)),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                isPlanar: false, colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0) else {
                throw CocoaError(.fileWriteUnknown)
            }
            scaled.size = host.bounds.size
            bitmap = scaled
        } else {
            guard let screenBitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            bitmap = screenBitmap
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: output.appendingPathComponent("\(name).png"))
        print("Rendered \(name)")
    }
}
