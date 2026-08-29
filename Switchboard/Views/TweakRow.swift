import AppKit
import SwiftUI

struct TweakRow: View {
    let tweak: Tweak
    @ObservedObject var store: TweakStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tweak.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.primary)
                if let subtitle = tweak.subtitle {
                    Text(subtitle)
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, tweak.subtitle == nil ? 9 : 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var control: some View {
        switch tweak.control {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { store.isOn(tweak) },
                set: { store.setOn(tweak, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel(tweak.title)
        case .choice(let choices):
            ChoicePicker(tweak: tweak, choices: choices, store: store)
        case .folder:
            FolderButton(title: tweak.title, path: store.stringValue(tweak)) { url in
                store.select(.string(url.path), for: tweak)
            }
        case .button(let label):
            Button(label) { store.perform(tweak) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(tweak.title)
        }
    }
}

private struct ChoicePicker: View {
    let tweak: Tweak
    let choices: [Choice]
    @ObservedObject var store: TweakStore

    private var options: [Choice] {
        if store.selectedChoice(tweak, among: choices) != nil {
            return choices
        }
        if let current = store.stringValue(tweak), !current.isEmpty {
            return [Choice(label: "Current (\(current.uppercased()))",
                           value: .string(current))] + choices
        }
        return choices
    }

    private var selection: Binding<String> {
        Binding(
            get: { store.selectedChoice(tweak, among: options)?.label ?? options[0].label },
            set: { label in
                if let choice = options.first(where: { $0.label == label }) {
                    store.select(choice.value, for: tweak)
                }
            }
        )
    }

    var body: some View {
        Picker(tweak.title, selection: selection) {
            ForEach(options) { choice in
                Text(choice.label).tag(choice.label)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 125)
    }
}

private struct FolderButton: View {
    let title: String
    let path: String?
    let onPick: (URL) -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 4) {
                Text(label).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: 135)
        .accessibilityLabel("\(title): \(label)")
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
        let startingPath = path.flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/Desktop"
        panel.directoryURL = URL(fileURLWithPath: startingPath, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}
