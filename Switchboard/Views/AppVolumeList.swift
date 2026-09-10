import AppKit
import SwiftUI

/// Apps come from live audio streams rather than the static settings catalog.
struct AppVolumeList: View {
    @ObservedObject var store: TweakStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App volume")
                        .font(.sectionHeader)
                        .foregroundStyle(Theme.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Adjust each app independently.")
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text("\(store.audioApps.count) \(store.audioApps.count == 1 ? "app" : "apps")")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if store.audioApps.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "speaker.wave.2")
                            .font(.emptyStateGlyph)
                            .foregroundStyle(Theme.secondary)
                            .accessibilityHidden(true)
                        Text("No audio apps yet")
                            .font(.rowTitle.weight(.medium))
                            .foregroundStyle(Theme.primary)
                        Text("Play something in an app to see its volume and output controls here.")
                            .font(.rowSubtitle)
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                } else {
                    ForEach(Array(store.audioApps.enumerated()), id: \.element.id) { index, app in
                        AppVolumeRow(app: app, store: store)
                        if index < store.audioApps.count - 1 {
                            Hairline().padding(.horizontal, Theme.rowInset)
                        }
                    }
                }
            }
            .groupSurface()

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Device volume affects every app playing through that output.")
                        .font(.rowSubtitle).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.audioOutputDevices.isEmpty {
                        Text("No output devices connected.")
                            .font(.rowSubtitle).foregroundStyle(Theme.secondary)
                    }
                    ForEach(store.audioOutputDevices) { device in
                        OutputDeviceVolumeRow(device: device, store: store)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack(spacing: 10) {
                    RowIcon(symbol: "speaker.wave.2")
                    Text("Output devices")
                        .font(.rowTitle.weight(.medium))
                        .foregroundStyle(Theme.primary)
                    Spacer(minLength: 4)
                    Text("\(store.audioOutputDevices.count) connected")
                        .font(.rowSubtitle).foregroundStyle(Theme.secondary)
                }
            }
            .disclosureGroupStyle(AudioDisclosureStyle())
            .groupSurface()

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your first adjustment asks for System Audio Recording access.")
                    Text("macOS shows a purple privacy indicator while an app's volume is reduced or its output is changed. Reset app audio to stop all audio access.")
                }
                .font(.rowSubtitle)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack(spacing: 10) {
                    RowIcon(symbol: "info.circle")
                    Text("About app audio")
                        .font(.rowTitle)
                        .foregroundStyle(Theme.primary)
                    Spacer(minLength: 0)
                }
            }
            .disclosureGroupStyle(AudioDisclosureStyle())
            .groupSurface()

            HStack {
                Text(store.hasAdjustedAudio ? "Custom app audio is active" : "Using default app audio")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button("Reset app audio") { store.resetAudioVolumes() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!store.hasAdjustedAudio)
                    .help("Restore every app to full volume and the system default output.")
            }
            .padding(.horizontal, 4)
        }
        // The store's one timer must stop polling when the audio list leaves the screen.
        .onAppear { store.setAudioListVisible(true) }
        .onDisappear { store.setAudioListVisible(false) }
    }
}

private struct AudioDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    configuration.label
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.rowInset)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rowHoverHighlight()
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(configuration.isExpanded ? "Hide details" : "Show details")

            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, Theme.rowInset)
                    .padding(.bottom, Theme.rowInset)
            }
        }
    }
}

private struct OutputDeviceVolumeRow: View {
    let device: AudioOutputDevice
    @ObservedObject var store: TweakStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(device.name)
                    .font(.rowTitle.weight(.medium))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .help(device.name)
                Spacer(minLength: 4)
                if device.uid == store.systemDefaultOutputUID {
                    Text("System Default").font(.rowSubtitle).foregroundStyle(Theme.secondary)
                }
            }
            switch store.outputDeviceVolumes[device.uid] ?? .unavailable("Waiting for the device volume.") {
            case .available(let value, let writable):
                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { Double(value) },
                        set: { store.setOutputVolume(Float($0), for: device) }
                    ), in: 0...1)
                    .controlSize(.small)
                    .disabled(!writable)
                    .accessibilityLabel("\(device.name) output volume")
                    .accessibilityValue("\(Int((value * 100).rounded())) percent")
                    Text("\(Int((value * 100).rounded()))%")
                        .font(.rowSubtitle).monospacedDigit()
                        .foregroundStyle(Theme.primary)
                        .frame(width: 40, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                if !writable { status("Use this device's own volume controls.") }
            case .unsupported:
                status("Use this device's own volume controls.")
            case .unavailable(let message):
                status("Volume unavailable. Retrying automatically.")
                    .help(message)
            }
        }
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.rowSubtitle).foregroundStyle(Theme.secondary)
    }
}

private struct AppVolumeRow: View {
    let app: AudioApp
    @ObservedObject var store: TweakStore

    private var volume: Binding<Double> {
        Binding(
            get: { Double(store.volume(for: app)) },
            set: { store.setVolume(Float($0), for: app) }
        )
    }

    private var volumePercent: Int {
        Int((volume.wrappedValue * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 24))
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.rowTitle.weight(.medium))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        .help(app.name)
                    Text(app.isPlaying ? "Playing" : "Not playing")
                        .font(.rowSubtitle)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Text("\(volumePercent)%")
                    .font(.system(size: NSFont.systemFontSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
            }

            Slider(value: volume, in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("\(app.name) volume")
                .accessibilityValue("\(volumePercent) percent")

            HStack(spacing: 8) {
                Text("Output")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                OutputDeviceMenu(app: app, store: store)
            }
        }
        .padding(Theme.rowInset)
        .contentShape(Rectangle())
        .rowHoverHighlight()
    }
}

/// A missing saved output stays visible so fallback does not look like a lost preference.
private struct OutputDeviceMenu: View {
    let app: AudioApp
    @ObservedObject var store: TweakStore

    private var selection: (uid: String?, isMissing: Bool) { store.outputSelection(for: app) }

    private var title: String {
        guard let uid = selection.uid else { return "System Default" }
        if selection.isMissing { return "Chosen device unavailable" }
        return store.audioOutputDevices.first { $0.uid == uid }?.name ?? "System Default"
    }

    var body: some View {
        Menu {
            Button {
                store.setOutputDevice(nil, for: app)
            } label: {
                if selection.uid == nil {
                    Label("System Default", systemImage: "checkmark")
                } else {
                    Text("System Default")
                }
            }
            if !store.audioOutputDevices.isEmpty {
                Divider()
                ForEach(store.audioOutputDevices) { device in
                    Button {
                        store.setOutputDevice(device.uid, for: app)
                    } label: {
                        if selection.uid == device.uid {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if selection.isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                }
                Text(title).lineLimit(1)
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .font(.rowSubtitle)
        .foregroundStyle(Theme.primary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityLabel("\(app.name) output device")
        .accessibilityValue(title)
        .help(title)
    }
}
