import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(panelShortcut: GlobalShortcut?, openPanel: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Welcome"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = NSHostingView(rootView: WelcomeView(
            panelShortcut: panelShortcut,
            close: { [weak window] in window?.performClose(nil) },
            openPanel: { [weak window] in
                window?.performClose(nil)
                openPanel()
            }
        ))
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func open() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}

private struct WelcomeFeature: Identifiable {
    let title: String
    let detail: String
    let symbol: String
    var id: String { title }
}

private struct WelcomeView: View {
    let panelShortcut: GlobalShortcut?
    let close: () -> Void
    let openPanel: () -> Void

    private let features = [
        WelcomeFeature(title: "Tweaks",
                       detail: "Keep your Mac awake, copy text from the screen, and adjust Finder, screenshot, and Dock settings.",
                       symbol: "slider.horizontal.3"),
        WelcomeFeature(title: "Audio",
                       detail: "Set the volume and output device for each app.",
                       symbol: "speaker.wave.2"),
        WelcomeFeature(title: "Clipboard",
                       detail: "Copy any of your last 20 text and image clips again.",
                       symbol: "doc.on.clipboard"),
        WelcomeFeature(title: "System",
                       detail: "Check CPU, GPU, memory, network, disk, and battery readings.",
                       symbol: "gauge.with.dots.needle.50percent"),
        WelcomeFeature(title: "Window snapping",
                       detail: "Move windows into halves, thirds, and quarters. Switch it on in Everyday.",
                       symbol: "rectangle.split.2x1"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(.brandMark)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Switchboard")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    menuBarHint
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(spokenMenuBarHint)
                }
            }
            VStack(spacing: 0) {
                ForEach(features) { feature in
                    featureRow(feature)
                    if feature.id != features.last?.id { Hairline() }
                }
            }
            .groupSurface()
            Text("macOS asks for access the first time you use a feature that needs it. Keyboard shortcuts and Launch at Login are in the panel's settings gear.")
                .font(.rowSubtitle)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Open Switchboard", action: openPanel)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .font(.bodyText)
        .foregroundStyle(Theme.primary)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // The template icon is the one in the menu bar, which is easier to spot
    // than a description of where it sits.
    private var menuBarHint: Text {
        let click = Text("Switchboard lives in the menu bar. Click \(Image(nsImage: MenuBarIcon.image)) to open it")
        guard let panelShortcut else { return click + Text(".") }
        return click + Text(", or press \(panelShortcut.label) from any app.")
    }

    private var spokenMenuBarHint: String {
        let click = "Switchboard lives in the menu bar. Click its icon to open it"
        guard let panelShortcut else { return click + "." }
        return click + ", or press \(panelShortcut.spokenLabel) from any app."
    }

    private func featureRow(_ feature: WelcomeFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(symbol: feature.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.rowTitle)
                Text(feature.detail)
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}
