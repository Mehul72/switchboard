import AppKit
import SwiftUI

/// The audio tab is a live list of whatever can currently make noise, so unlike
/// every other tab it is not backed by the static catalog.
struct AppVolumeList: View {
    @ObservedObject var store: TweakStore

    // Apps start and stop playing while the panel is open.
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
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
        }
        .background(Theme.groupBackground, in: RoundedRectangle(cornerRadius: 10))
        .onAppear { store.refreshAudioApps() }
        .onReceive(refresh) { _ in store.refreshAudioApps() }
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

    var body: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}
