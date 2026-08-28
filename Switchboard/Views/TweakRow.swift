import AppKit
import SwiftUI

struct TweakRow: View {
    let tweak: Tweak
    @ObservedObject var store: TweakStore

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.primary)
                if let subtitle = tweak.subtitle {
                    Text(subtitle)
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: tweak.subtitle == nil ? 34 : 46)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.hover)
                .opacity(hovering ? 1 : 0)
                .padding(.horizontal, 6)
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var control: some View {
        switch tweak.control {
        case .toggle:
            SwitchboardToggle(isOn: store.isOn(tweak)) { store.setOn(tweak, $0) }
        case .choice(let choices):
            ChoicePicker(choices: choices,
                         selected: store.selectedChoice(tweak, among: choices)) {
                store.select($0, for: tweak)
            }
        case .folder:
            FolderButton(path: store.stringValue(tweak)) { url in
                store.select(.string(url.path), for: tweak)
            }
        }
    }
}

private struct ChoicePicker: View {
    let choices: [Choice]
    let selected: Choice?
    let onSelect: (PrefValue) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.label) { choice in
                let active = choice == selected
                Text(choice.label)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.primary)
                    .opacity(active ? 1 : 0.35)
                    .frame(width: 34, height: 20)
                    .background {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.trackOff)
                            .opacity(active ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(choice.value) }
                    .pointingHand()
            }
        }
    }
}

private struct FolderButton: View {
    let path: String?
    let onPick: (URL) -> Void

    var body: some View {
        Text(label)
            .font(.system(size: 11))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: 150, alignment: .trailing)
            .contentShape(Rectangle())
            .onTapGesture(perform: choose)
            .pointingHand()
    }

    private var label: String {
        guard let path, !path.isEmpty else { return "Desktop" }
        return (path as NSString).lastPathComponent
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}
