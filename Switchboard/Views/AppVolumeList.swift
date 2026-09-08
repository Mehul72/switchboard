import AppKit
import SwiftUI

/// The audio tab is a live list of whatever can currently make noise, so unlike
/// every other tab it is not backed by the static catalog.
struct AppVolumeList: View {
    @ObservedObject var store: TweakStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apps").font(.rowTitle)
                Text("macOS shows a purple audio privacy dot while an app's volume is reduced or its output is changed. Reset to stop all audio access.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reset App Volumes and Outputs") { store.resetAudioVolumes() }
                    .controlSize(.small)
                    .disabled(!store.hasAdjustedAudio)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            Divider()
            if store.audioApps.isEmpty {
                Text("No apps currently have an audio stream.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ForEach(Array(store.audioApps.enumerated()), id: \.element.id) { index, app in
                    AppVolumeRow(app: app, store: store)
                    if index < store.audioApps.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            Divider()
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
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
                Text("Output devices").font(.rowTitle)
            }
            .disclosureGroupStyle(OutputDevicesDisclosureStyle())
        }
        .background(Theme.groupBackground, in: RoundedRectangle(cornerRadius: 10))
        // Apps start and stop playing while the panel is open, and the store
        // owns the one timer that notices, so it has to know we are on screen.
        .onAppear { store.setAudioListVisible(true) }
        .onDisappear { store.setAudioListVisible(false) }
    }
}

private struct OutputDevicesDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")

            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct OutputDeviceVolumeRow: View {
    let device: AudioOutputDevice
    @ObservedObject var store: TweakStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.name).font(.rowSubtitle).lineLimit(1)
                if device.uid == store.systemDefaultOutputUID {
                    Text("System Default").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
            }
            switch store.outputDeviceVolumes[device.uid] ?? .unavailable("Waiting for the device volume.") {
            case .available(let value, let writable):
                HStack {
                    Slider(value: Binding(
                        get: { Double(value) },
                        set: { store.setOutputVolume(Float($0), for: device) }
                    ), in: 0...1)
                    .controlSize(.small)
                    .disabled(!writable)
                    .accessibilityLabel("\(device.name) output volume")
                    Text("\(Int((value * 100).rounded()))%")
                        .font(.system(size: 10.5)).monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 34, alignment: .trailing)
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
        Text(text).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
    }
}

private struct AppVolumeRow: View {
    let app: AudioApp
    @ObservedObject var store: TweakStore

    /// The icon's width plus its spacing, so the output menu lines up under the
    /// app's name rather than under its icon.
    private static let nameColumnInset: CGFloat = 32

    private var volume: Binding<Double> {
        Binding(
            get: { Double(store.volume(for: app)) },
            set: { store.setVolume(Float($0), for: app) }
        )
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed").font(.system(size: 15))
                    }
                }
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.rowTitle)
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                    Text(app.isPlaying ? "Playing" : "Idle")
                        .font(.system(size: 10))
                        .foregroundStyle(app.isPlaying ? Color.accentColor : Theme.tertiary)
                }
                .frame(width: 108, alignment: .leading)

                Slider(value: volume, in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("\(app.name) volume")

                Text("\(Int((volume.wrappedValue * 100).rounded()))%")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            HStack(spacing: 0) {
                Spacer().frame(width: Self.nameColumnInset)
                OutputDeviceMenu(app: app, store: store)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Sends one app to an output device of its own. Following the system default
/// is the first entry rather than an absence, because "no choice" and "the
/// device that happens to be default" behave differently when that default
/// changes.
private struct OutputDeviceMenu: View {
    let app: AudioApp
    @ObservedObject var store: TweakStore

    private var selection: (uid: String?, isMissing: Bool) {
        store.outputSelection(for: app)
    }

    /// A chosen device that has been unplugged says so. The app is already back
    /// on the default, and showing the default's name would hide that.
    private var title: String {
        guard let uid = selection.uid else { return "System Default" }
        if selection.isMissing { return "Chosen device unavailable" }
        return store.audioOutputDevices.first { $0.uid == uid }?.name ?? "System Default"
    }

    var body: some View {
        Menu {
            Button("System Default") { store.setOutputDevice(nil, for: app) }
            if !store.audioOutputDevices.isEmpty {
                Divider()
                ForEach(store.audioOutputDevices) { device in
                    Button(device.name) { store.setOutputDevice(device.uid, for: app) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: selection.isMissing
                      ? "exclamationmark.triangle.fill"
                      : "hifispeaker")
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .foregroundStyle(selection.isMissing ? Color.orange : Theme.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("\(app.name) output device")
    }
}
