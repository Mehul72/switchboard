import AppKit
import SwiftUI

extension DocumentationRenderer {
    @MainActor
    static func renderFeatures(store: TweakStore, appearance: AppearanceSetting, output: URL) async throws {
        let savedVolumes = store.audioVolumes
        let savedRoutes = store.audioRoutes
        let savedClips = store.clips
        let savedNotice = store.notice
        defer {
            store.audioVolumes = savedVolumes
            store.audioRoutes = savedRoutes
            store.clips = savedClips
            store.notice = savedNotice
        }
        appearance.choice = .dark
        for step in 0..<4 {
            store.audioVolumes = Dictionary(uniqueKeysWithValues: store.audioApps.map { ($0.bundleID, Float(1)) })
            store.audioRoutes = [:]
            if step == 1 || step == 2 { store.audioVolumes["com.apple.Music"] = 0.35 }
            if step == 2 { store.audioRoutes["com.apple.Music"] = "headphones" }
            try await capture(AppVolumeList(store: store).padding(16).background(Theme.canvas)
                .preferredColorScheme(.dark), name: "audio-step-\(step)",
                size: NSSize(width: 440, height: 575), dark: true, output: output, naturalHeight: true)
        }

        appearance.choice = .light
        try await capture(CaptureSample(), name: "text-source", size: NSSize(width: 600, height: 370),
                          dark: false, output: output)
        let image = try Data(contentsOf: output.appendingPathComponent("text-source.png"))
        let recognised = try await Task.detached { try TextCapture.recognise(image).get() }.value
        guard recognised.contains("Team meeting"), recognised.contains("Tuesday, 10:30"),
              recognised.contains("Bring the draft budget.") else {
            throw NSError(domain: "Documentation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Sample text recognition changed: \(recognised)"])
        }
        try Data(recognised.utf8).write(to: output.appendingPathComponent("recognised-text.txt"))
        store.clips = [ClipEntry(text: recognised, imageData: nil, pixelSize: nil, date: Date(),
                                note: "Captured from the screen")]
        try await capture(ClipboardHistoryList(store: store).padding(16).background(Theme.canvas)
            .preferredColorScheme(.light), name: "text-result", size: NSSize(width: 440, height: 200),
            dark: false, output: output, naturalHeight: true)

        let directory = output.appendingPathComponent("Sample files")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A real image gives the shelf a Quick Look thumbnail instead of a blank page.
        try await capture(SampleArtwork(), name: "Moodboard", size: NSSize(width: 480, height: 360),
                          dark: false, output: directory)
        let artwork = directory.appendingPathComponent("Moodboard.png")
        let notes = directory.appendingPathComponent("Launch notes.txt")
        try Data("Check the download link before publishing.".utf8).write(to: notes)
        let assets = directory.appendingPathComponent("Design assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let drive = ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "sample-drive")
        var mounted = [drive]
        // Stands in for macOS so the shelf's own eject handling can run; it only edits this sample list.
        let volumes = ShelfVolumes(load: { $0(.success(mounted)) }, eject: { volume, done in
            mounted.removeAll { $0.id == volume.id }
            done(.success(()))
        })
        volumes.refresh()
        let shelf = FileShelf()
        let drag = ShelfDragState()
        for step in 0..<3 {
            switch step {
            case 0:
                drag.enter([artwork])
            case 1:
                shelf.add([artwork])
                drag.finish()
            default:
                shelf.add([notes, assets])
                // The previous frame already shows the confirmation.
                shelf.notice = nil
            }
            try await capture(FileShelfView(shelf: shelf, volumes: volumes, drag: drag, addFiles: {}, close: {})
                .preferredColorScheme(.light), name: "shelf-step-\(step)",
                size: NSSize(width: FileShelfController.width, height: 380), dark: false,
                output: output, naturalHeight: true)
        }
        drag.enter([drive.url])
        try await capture(FileShelfView(shelf: shelf, volumes: volumes, drag: drag, addFiles: {}, close: {})
            .preferredColorScheme(.light), name: "disk-target", size: NSSize(width: FileShelfController.width, height: 400),
            dark: false, output: output, naturalHeight: true)
        drag.finish()
        volumes.eject(drive)
        guard volumes.volumes.isEmpty, volumes.notice?.isError == false else {
            throw NSError(domain: "Documentation", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Sample eject did not finish: \(String(describing: volumes.notice))"])
        }
        try await capture(FileShelfView(shelf: shelf, volumes: volumes, drag: drag, addFiles: {}, close: {})
            .preferredColorScheme(.light), name: "disk-ejected", size: NSSize(width: FileShelfController.width, height: 380),
            dark: false, output: output, naturalHeight: true)
        guard [artwork, notes, assets].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }
    }
}

private struct SampleArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.63, blue: 0.45), Color(red: 0.52, green: 0.36, blue: 0.86)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.32)).frame(width: 200).offset(x: -95, y: -45)
            Circle().fill(Color(red: 1, green: 0.86, blue: 0.42)).frame(width: 120).offset(x: 120, y: 80)
        }
    }
}

private struct CaptureSample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Team meeting\nTuesday, 10:30")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.23, blue: 0.3))
            Text("Bring the draft budget.")
                .font(.system(size: 24))
                .foregroundStyle(Color(red: 0.25, green: 0.37, blue: 0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(48)
        .background(Color(red: 0.89, green: 0.96, blue: 0.94))
    }
}
