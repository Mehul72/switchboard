import AppKit
import SwiftUI

struct TweakRow: View {
    let tweak: Tweak
    @ObservedObject var store: TweakStore

    var body: some View {
        HStack(alignment: .center, spacing: Theme.rowSpacing) {
            RowIcon(symbol: tweak.symbol)

            VStack(alignment: .leading, spacing: 3) {
                // The title is the whole point of the row, so it wraps rather
                // than truncating -- a clipped setting name is unreadable.
                Text(tweak.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // While a setting is running, what it is doing right now
                // beats the description of what it would do.
                if let span = liveSpan {
                    AwakeStatusLabel(span: span)
                } else if isReadingScreenText {
                    Text("Reading the text…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                } else if let subtitle = tweak.subtitle {
                    Text(subtitle)
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A fixed column keeps every control on the same edge and stops a
            // wide picker from squeezing the label next to it. This frame is
            // the only one that places a control: a menu or picker is as wide
            // as its label, and a second frame around it centred the narrow
            // ones in the column instead of leaving them on the trailing edge.
            control
                .frame(maxWidth: Theme.controlColumn, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .rowHoverHighlight()
    }

    private var isReadingScreenText: Bool {
        guard case .regionOCR = tweak.behavior else { return false }
        return store.isReadingScreenText
    }

    private var liveSpan: AwakeSpan? {
        guard case .keepAwake = tweak.behavior else { return nil }
        return store.keepAwakeSpan
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
            .controlSize(.small)
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
                .disabled(!store.canPerform(tweak))
                .accessibilityLabel(tweak.title)
        case .keepAwake:
            KeepAwakeMenu(title: tweak.title, store: store)
        }
    }
}

/// A menu rather than a picker: running apps need a submenu, and the display
/// option is a checkbox that applies to whichever mode is chosen.
private struct KeepAwakeMenu: View {
    let title: String
    @ObservedObject var store: TweakStore

    var body: some View {
        Menu {
            option("Off", .off)
            ForEach(AwakeDuration.choices, id: \.self) { minutes in
                option(AwakeDuration.label(minutes: minutes), .minutes(minutes))
            }
            option("Until I stop it", .untilStopped)
            Divider()
            Menu("Until an app quits") {
                let apps = AwakeApp.running()
                if apps.isEmpty {
                    Text("No other apps are open")
                }
                ForEach(apps) { app in
                    option(app.name, .untilAppQuits(pid: app.pid, name: app.name))
                }
            }
            if PowerSnapshot.machineHasBattery {
                option("While plugged in", .whilePluggedIn)
            }
            Divider()
            Toggle("Let display sleep", isOn: Binding(
                get: { store.keepAwakeAllowsDisplaySleep },
                set: { store.setKeepAwakeAllowsDisplaySleep($0) }
            ))
        } label: {
            Text(currentLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .controlSize(.small)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(title)
        .accessibilityValue(currentLabel)
    }

    /// A checkmark item. Choosing the item that is already checked keeps it,
    /// the way a picker would, instead of switching keep awake off.
    private func option(_ label: String, _ mode: AwakeMode) -> some View {
        Toggle(label, isOn: Binding(
            get: { store.keepAwakeMode == mode },
            set: { chosen in if chosen { store.setKeepAwake(mode) } }
        ))
    }

    private var currentLabel: String {
        switch store.keepAwakeMode {
        case .off: return "Off"
        case .minutes(let minutes): return AwakeDuration.label(minutes: minutes)
        case .untilStopped: return "Until I stop it"
        case .untilAppQuits(_, let name): return "Until \(name) quits"
        case .whilePluggedIn: return "While plugged in"
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
            get: { store.selectedChoice(tweak, among: options)?.label ?? options.first?.label ?? "" },
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
    }
}

/// Counts on the timeline rather than a stored timer, so it ticks only while
/// the row is on screen.
private struct AwakeStatusLabel: View {
    let span: AwakeSpan

    var body: some View {
        // The schedule only decides when to redraw. Its entry date trails the
        // real clock by up to one tick, and rounding up turns that fraction of
        // a second into a whole extra minute, so the wording reads the clock.
        TimelineView(.periodic(from: span.startedAt, by: 1)) { _ in
            if let status = AwakeStatus.text(for: span, now: Date()) {
                Text(status)
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
                    .accessibilityLabel(status)
            }
        }
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
