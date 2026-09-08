import AppKit
import Charts
import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var openError: String?

    private var reading: SystemReading { monitor.reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SYSTEM").font(.sectionHeader).foregroundStyle(Theme.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Group {
                        if !monitor.isRunning {
                            Text("Paused")
                        } else if context.date.timeIntervalSince(reading.date) > 6 {
                            Text("Updates delayed").foregroundStyle(.orange)
                        } else if monitor.history.isEmpty {
                            Text("Measuring…")
                        } else if !reading.unavailable.isEmpty {
                            Text("Some data unavailable").foregroundStyle(.orange)
                        } else {
                            Text("Live")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("CPU", value: percent(reading.cpu), detail: "All cores", color: .blue, key: \.cpu)
                metric("GPU", value: percent(reading.gpu), detail: "Busiest GPU", color: .purple, key: \.gpu)
                metric("Memory", value: bytes(reading.memoryUsed),
                       detail: "of \(bytes(reading.memoryTotal))", color: .orange, key: \.memoryUsed,
                       maximum: reading.memoryTotal)
                metric("Swap", value: bytes(reading.swapUsed), detail: "Used on disk", color: .pink,
                       key: \.swapUsed, maximum: max(1, monitor.history.compactMap(\.swapUsed).max() ?? 1))
            }
            panel {
                Text("Network").font(.rowTitle)
                HStack {
                    Label(rate(reading.network?.received), systemImage: "arrow.down.circle")
                        .accessibilityLabel("Download " + rate(reading.network?.received))
                    Spacer()
                    Label(rate(reading.network?.sent), systemImage: "arrow.up.circle")
                        .accessibilityLabel("Upload " + rate(reading.network?.sent))
                }
                .font(.system(size: 12, design: .monospaced))
                Text("Wi-Fi and Ethernet combined").font(.rowSubtitle).foregroundStyle(Theme.secondary)
            }
            panel {
                HStack {
                    Text("Power").font(.rowTitle)
                    Spacer()
                    Text(reading.power.state).foregroundStyle(Theme.secondary)
                }
                if let charge = reading.power.charge {
                    detail("Battery", percent(charge))
                    ProgressView(value: charge, total: 100).tint(.green)
                    if let minutes = reading.power.minutesRemaining {
                        detail(reading.power.state == "Charging" ? "Until full" : "Time remaining",
                               "\(minutes / 60)h \(minutes % 60)m")
                    }
                    detail("Cycle count", reading.power.cycles.map(String.init) ?? "Unavailable")
                    detail("Battery temperature", reading.power.temperature.map { String(format: "%.1f °C", $0) }
                           ?? "Unavailable")
                    detail("Battery power", reading.power.watts.map { String(format: "%.1f W", $0) }
                           ?? "Unavailable")
                }
                detail("Thermal state", thermalLabel)
            }
            panel {
                detail("Disk space", "\(bytes(reading.diskFree)) free of \(bytes(reading.diskTotal))")
                if let free = reading.diskFree, let total = reading.diskTotal, total > 0 {
                    ProgressView(value: min(total, max(0, total - free)), total: total)
                }
            }
            if !reading.unavailable.isEmpty {
                Text("Could not read: " + reading.unavailable.joined(separator: ", ") + ". Retrying automatically.")
                    .font(.rowSubtitle).foregroundStyle(.orange)
            }
            Text("Graphs show up to two minutes while this panel is open. GPU and battery sensors may be unavailable on some Macs.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Activity Monitor", action: openActivityMonitor)
                .buttonStyle(.borderless)
            if let openError {
                Text(openError).font(.rowSubtitle).foregroundStyle(.red)
            }
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func metric(_ title: String, value: String, detail: String, color: Color,
                        key: KeyPath<SystemReading, Double?>, maximum: Double = 100) -> some View {
        panel {
            Text(title).font(.rowTitle).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit()
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            Chart {
                ForEach(Array(monitor.history.enumerated()), id: \.offset) { index, sample in
                    if let value = sample[keyPath: key] {
                        LineMark(x: .value("Time", sample.date), y: .value(title, value),
                                 series: .value("Segment", segment(at: index, key: key)))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .chartYScale(domain: 0...max(1, maximum))
            .chartXScale(domain: reading.date.addingTimeInterval(-120)...reading.date)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 30)
            .accessibilityLabel("\(title) history, current value \(value)")
        }
    }

    private func segment(at index: Int, key: KeyPath<SystemReading, Double?>) -> Int {
        monitor.history.prefix(index).filter { $0[keyPath: key] == nil }.count
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .font(.rowSubtitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(Theme.groupBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.groupBorder))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "Unavailable"
    }

    private func bytes(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func rate(_ value: Double?) -> String {
        value.map { bytes($0) + "/s" } ?? "Measuring…"
    }

    private var thermalLabel: String {
        switch reading.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "High"
        case .critical: return "Critical"
        @unknown default: return "Unavailable"
        }
    }

    private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else {
            openError = "Activity Monitor could not be found. Open it from Applications > Utilities."
            return
        }
        openError = nil
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                DispatchQueue.main.async { openError = "Activity Monitor could not be opened. Try opening it from Finder." }
            }
        }
    }
}
