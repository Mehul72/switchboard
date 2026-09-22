import AppKit
import SwiftUI

@MainActor
final class WindowSwitcherPanel: NSPanel {
    private let displayFrame: CGRect

    init(model: WindowSwitcher, screen: NSScreen?) {
        displayFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        title = "Window switcher"
        setAccessibilityLabel("Window switcher")
        let content = NSHostingView(rootView: WindowSwitcherView(model: model))
        content.sizingOptions = []
        content.autoresizingMask = [.width, .height]
        contentView = content
        fit(windowCount: 0, appCount: 0)
    }

    /// Up to three rows of window cards and two rows of app tiles show before scrolling.
    func fit(windowCount: Int, appCount: Int) {
        let width = min(940, displayFrame.width - 40)
        let windowColumns = max(1, Int((width - 40) / 216))
        let windowRows = min(3, Int(ceil(Double(windowCount) / Double(windowColumns))))
        let appColumns = max(1, Int((width - 40) / 172))
        let appRows = min(2, Int(ceil(Double(appCount) / Double(appColumns))))
        let appsHeight: CGFloat = appRows == 0 ? 0 : CGFloat(appRows) * 58 + 34
        let contentHeight = max(CGFloat(windowRows) * 190 + appsHeight, 190)
        let height = min(contentHeight + 124, displayFrame.height - 40)
        setFrame(CGRect(x: displayFrame.midX - width / 2, y: displayFrame.midY - height / 2,
                       width: width, height: height), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct WindowSwitcherView: View {
    @ObservedObject var model: WindowSwitcher

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.sameAppOnly ? "This app’s windows" : "Switch windows")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(model.isLoading ? "" : windowCount)
                    .foregroundStyle(Theme.secondary)
                Button(action: model.cancel) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel window switching")
            }
            if model.isLoading {
                ProgressView("Finding windows…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                                ForEach(model.windows.filter { !$0.isWindowlessApp }) { window in
                                    card(window).id(window.id)
                                        .onAppear { model.previewNeeded(window.id) }
                                }
                            }
                            let apps = model.windows.filter(\.isWindowlessApp)
                            if !apps.isEmpty {
                                Text("Apps without windows")
                                    .font(.rowSubtitle.weight(.semibold))
                                    .foregroundStyle(Theme.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                                    ForEach(apps) { app in appTile(app).id(app.id) }
                                }
                            }
                        }.padding(3)
                    }
                    .onChange(of: model.selectedID) { _, selected in
                        if let selected { reader.scrollTo(selected, anchor: .center) }
                    }
                    .onAppear {
                        if let selected = model.selectedID { reader.scrollTo(selected, anchor: .center) }
                    }
                }
            }
            HStack {
                Text("Tab / ← → to move · Q to quit app · Release modifier to switch · Esc to cancel")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if !model.hasPreviewsPermission {
                    Button("Enable Previews", action: model.requestPreviews)
                        .help("Allow Screen Recording to see window previews. Icons and titles work without it.")
                }
            }
        }
        .padding(20)
        .foregroundStyle(Theme.primary)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.secondary, lineWidth: 1) }
    }

    private var windowCount: String {
        let count = model.windows.filter { !$0.isWindowlessApp }.count
        return count == 1 ? "1 window" : "\(count) windows"
    }

    private func appTile(_ app: SwitcherWindow) -> some View {
        let selected = model.selectedID == app.id
        let icon = NSRunningApplication(processIdentifier: app.pid)?.icon
        return Button { model.choose(app.id) } label: {
            HStack(spacing: 8) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                else { Image(systemName: "app").font(.title2).frame(width: 28, height: 28) }
                Text(app.appName).font(.rowTitle.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(selected ? Theme.selectionBackground : Theme.groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Theme.groupBorder,
                                                               lineWidth: selected ? 3 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            if case .active = phase { model.hover(app.id) }
        }
        .help("\(app.appName): no open windows")
        .accessibilityLabel("\(app.appName), no open windows")
        .accessibilityValue([selected ? "Selected" : nil, app.isHidden ? "Hidden" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Switch to this app")
    }

    private func card(_ window: SwitcherWindow) -> some View {
        let selected = model.selectedID == window.id
        let icon = NSRunningApplication(processIdentifier: window.pid)?.icon
        return Button { model.choose(window.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Theme.controlBackground
                    if let image = model.images[window.id] {
                        Image(nsImage: image).resizable().scaledToFit().padding(4)
                    } else if let icon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 56, height: 56)
                    } else {
                        Image(systemName: "macwindow").font(.largeTitle)
                    }
                }
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                HStack(spacing: 6) {
                    if let icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                    Text(window.appName).font(.rowTitle.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                }
                HStack(spacing: 4) {
                    if window.isMinimized { Image(systemName: "minus.square").help("Minimized") }
                    else if window.isHidden { Image(systemName: "eye.slash").help("Hidden") }
                    Text(window.title).lineLimit(1).truncationMode(.middle)
                }
                .font(.rowSubtitle)
                .foregroundStyle(Theme.secondary)
            }
            .padding(10)
            .background(selected ? Theme.selectionBackground : Theme.groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Theme.groupBorder,
                                                               lineWidth: selected ? 3 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            if case .active = phase { model.hover(window.id) }
        }
        .help("\(window.appName): \(window.title)")
        .accessibilityLabel("\(window.appName), \(window.title)")
        .accessibilityValue([selected ? "Selected" : nil, window.isMinimized ? "Minimized" : nil,
                             window.isHidden ? "Hidden" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Switch to this window")
    }
}
