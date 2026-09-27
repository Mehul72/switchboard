import AppKit
import SwiftUI

// These fixtures must never enumerate, capture, focus, or quit a user's windows.
private final class DocumentationWindows: SwitcherWindowProviding {
    func snapshot(frontmostPID: pid_t?, sameAppOnly: Bool,
                  completion: @escaping (Result<SwitcherWindowSnapshot, Error>) -> Void) {
        preconditionFailure("Documentation cannot enumerate real windows")
    }
    func focus(_ target: SwitcherWindowTarget, completion: @escaping (Result<Void, Error>) -> Void) {
        preconditionFailure("Documentation cannot focus real windows")
    }
}

extension DocumentationRenderer {
    @MainActor
    static func renderWindowTools(output: URL) async throws {
        let titles = ["Design assets", "Launch checklist", "Release notes"]
        for (index, title) in titles.enumerated() {
            try await capture(ExampleDocument(title: title, style: index), name: "sample-window-\(index)",
                              size: NSSize(width: 680, height: 420), dark: false, output: output)
        }
        let model = WindowSwitcher(inventory: DocumentationWindows(), hasAccessibility: { false },
                                   canCapture: { false }, requestQuit: { _ in
            preconditionFailure("Documentation cannot quit apps")
        }, previews: SwitcherPreviews(capture: { _, _ in
            preconditionFailure("Documentation cannot capture real windows")
        }))
        model.windows = [
            SwitcherWindow(id: 1, pid: -101, appName: "Workspace", title: titles[0]),
            SwitcherWindow(id: 2, pid: -102, appName: "Notes", title: titles[1]),
            SwitcherWindow(id: 3, pid: -102, appName: "Notes", title: titles[2])
        ]
        for index in 0..<3 {
            guard let image = NSImage(contentsOf: output.appendingPathComponent("sample-window-\(index).png")) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            model.images[UInt32(index + 1)] = image
        }
        model.hasPreviewsPermission = true
        for index in 0..<3 {
            model.selectedID = UInt32(index + 1)
            let view = WindowSwitcherView(model: model).preferredColorScheme(.dark)
            try await capture(view, name: "switcher-\(index)", size: NSSize(width: 840, height: 290),
                              dark: true, output: output)
        }
        model.sameAppOnly = true
        model.windows.removeFirst()
        model.selectedID = 3
        try await capture(WindowSwitcherView(model: model).preferredColorScheme(.dark), name: "switcher-same-app",
                          size: NSSize(width: 840, height: 290), dark: true, output: output)

        let screen = CGRect(x: 0, y: 0, width: 960, height: 540)
        let original = CGRect(x: 230, y: 90, width: 600, height: 360)
        let placements: [(String, WindowPlacement?)] = [
            ("free", nil), ("half", .leftHalf), ("third", .centerThird),
            ("quarter", .topRight), ("maximise", .maximize)
        ]
        for (name, placement) in placements {
            let frame = placement.map { WindowLayout.frame(for: $0, window: original, in: screen) } ?? original
            let scene = ExampleDesktop(window: frame, highlight: nil)
            try await capture(scene, name: "snap-\(name)", size: screen.size, dark: false, output: output)
        }
        let anchor = GridCell(column: 0, row: 0)
        for (name, cell) in [("start", anchor), ("half", GridCell(column: 2, row: 1))] {
            let highlight = SnapGrid.frame(spanning: anchor, cell, in: screen)
            try await capture(ExampleDesktop(window: original, highlight: highlight), name: "grid-\(name)",
                              size: screen.size, dark: false, output: output)
        }
    }
}

private struct ExampleDocument: View {
    let title: String
    var style = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color.opacity(0.8)).frame(width: 10, height: 10)
                }
                Spacer()
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: style == 0 ? "square.grid.2x2" : "square.and.pencil")
            }
            .foregroundStyle(Color(red: 0.24, green: 0.29, blue: 0.35))
            .padding(12)
            .background(Color(red: 0.92, green: 0.94, blue: 0.97))
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Workspace", systemImage: "folder")
                    Label("Favourites", systemImage: "star")
                    Label("Recent", systemImage: "clock")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.37, green: 0.43, blue: 0.51))
                .frame(width: 100, alignment: .leading)
                VStack(alignment: .leading, spacing: 18) {
                    Text(title).font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.12, green: 0.17, blue: 0.24))
                    Text(style == 0 ? "Project files" : "Updated Monday")
                        .foregroundStyle(.secondary).font(.system(size: 14))
                    if style == 0 {
                        HStack(spacing: 24) {
                            ForEach(["Artwork", "Screenshots", "Documents"], id: \.self) { name in
                                VStack(spacing: 8) {
                                    Image(systemName: "folder.fill").font(.system(size: 36)).foregroundStyle(.blue)
                                    Text(name).font(.system(size: 11))
                                }
                            }
                        }
                    } else {
                        ForEach(style == 1 ? ["Check the download link", "Check the first launch", "Upload the disk image"] :
                                    ["Window previews", "File shelf", "Shortcut fixes"], id: \.self) { item in
                            Label(item, systemImage: style == 1 ? "checkmark.circle" : "circle.fill")
                                .font(.system(size: 14)).foregroundStyle(Color(red: 0.2, green: 0.35, blue: 0.47))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(0.12)) }
    }
}

private struct ExampleDesktop: View {
    let window: CGRect
    let highlight: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.13, green: 0.25, blue: 0.4),
                                    Color(red: 0.24, green: 0.46, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ExampleDocument(title: "Launch checklist")
                .frame(width: window.width, height: window.height)
                .clipped()
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .offset(x: window.minX, y: window.minY)
            if let highlight {
                DocumentationGrid(highlight: highlight)
            }
        }
        .frame(width: 960, height: 540)
        .clipped()
    }
}

private struct DocumentationGrid: NSViewRepresentable {
    let highlight: CGRect
    func makeNSView(context: Context) -> GridCanvas { GridCanvas() }
    func updateNSView(_ view: GridCanvas, context: Context) {
        view.screen = CGRect(x: 0, y: 0, width: 960, height: 540)
        view.highlight = highlight
    }
}
