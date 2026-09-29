import AppKit
import Charts
import SwiftUI

struct SystemMonitorView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var readout: MenuBarReadout
    @State private var openError: String?
    @State private var processSort = ProcessSort.cpu
    /// Row order captured when the pointer enters the list. Rows re-sort every
    /// sample, and a Quit click must not land on a row that just slid under it.
    @State private var frozenRows: [ProcessUsage]?
    @State private var quitRequests: [String: Date] = [:]
    @State private var quitError: String?

    private var reading: SystemReading { monitor.reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("System").font(.sectionHeader).foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Group {
                        if !monitor.isRunning {
                            Label("Paused", systemImage: "pause.circle")
                        } else if context.date.timeIntervalSince(reading.date) > 6 {
                            Label("Updates delayed", systemImage: "clock.badge.exclamationmark")
                        } else if monitor.history.isEmpty {
                            Label("Measuring…", systemImage: "waveform.path")
                        } else if !reading.unavailable.isEmpty {
                            Label("Some data unavailable", systemImage: "exclamationmark.circle")
                        } else {
                            Label("Live", systemImage: "waveform.path")
                        }
                    }
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.controlBackground, in: Capsule())
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("CPU", value: percent(reading.cpu), detail: "All cores", color: Theme.accent, key: \.cpu)
                metric("GPU", value: percent(reading.gpu), detail: "Busiest GPU", color: Theme.accent, key: \.gpu)
                metric("Memory", value: bytes(reading.memoryUsed),
                       detail: "of \(bytes(reading.memoryTotal))", color: Theme.accent, key: \.memoryUsed,
                       maximum: reading.memoryTotal)
                metric("Swap", value: bytes(reading.swapUsed), detail: "Used on disk", color: Theme.accent,
                       key: \.swapUsed, maximum: max(1, monitor.history.compactMap(\.swapUsed).max() ?? 1))
            }
            processPanel
            panel {
                Text("Network").font(.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
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
                    Text("Power").font(.sectionHeader)
                        .accessibilityAddTraits(.isHeader)
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
            readoutPanel
            if !reading.unavailable.isEmpty {
                message("Could not read: " + reading.unavailable.joined(separator: ", ") + ". Retrying automatically.",
                        symbol: "exclamationmark.circle")
            }
            message("Graphs show up to the last two minutes. GPU and battery sensors may be unavailable on some Macs.",
                    symbol: "info.circle")
            Button(action: openActivityMonitor) {
                Label("Open Activity Monitor", systemImage: "arrow.up.forward.app")
                    .frame(minHeight: 26)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            if let openError {
                message(openError, symbol: "exclamationmark.triangle")
            }
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .onChange(of: reading.date) { _, now in forgetSettledQuitRequests(now: now) }
    }

    private var readoutPanel: some View {
        panel {
            Text("Show in menu bar").font(.sectionHeader)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 14) {
                ForEach(ReadoutMetric.allCases.filter { $0 != .battery || PowerSnapshot.machineHasBattery }) { metric in
                    Toggle(metric.title, isOn: Binding(get: { readout.isShown(metric) },
                                                       set: { readout.setShown(metric, $0) }))
                        .toggleStyle(.checkbox)
                }
            }
            Text("Updates every two seconds, including while this panel is closed.")
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var processPanel: some View {
        panel {
            HStack {
                Text("Using the most").font(.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Picker("Sort processes by", selection: $processSort) {
                    ForEach(ProcessSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            let rows = displayedRows
            if rows.isEmpty {
                Text(processPlaceholder)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    ForEach(rows) { usage in
                        ProcessRow(usage: usage, value: processValue(usage),
                                   quittable: AppQuitter.quittableApp(for: usage) != nil,
                                   isQuitting: quitRequests[usage.id] != nil) { quit(usage) }
                    }
                }
                .onHover { hovering in frozenRows = hovering ? liveRows : nil }
            }
            if let quitError {
                Text(quitError)
                    .foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("CPU is a share of all cores. Quit asks an app to close the way the Dock does, so it can save your work.")
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: processSort) { _, _ in
            if frozenRows != nil { frozenRows = liveRows }
        }
    }

    private var liveRows: [ProcessUsage] {
        guard let processes = reading.processes else { return [] }
        return processSort == .cpu ? processes.byCPU : processes.byMemory
    }

    /// While frozen, rows keep their places but still show the latest figures
    /// when they have them.
    private var displayedRows: [ProcessUsage] {
        guard let frozenRows else { return liveRows }
        let latest = Dictionary(uniqueKeysWithValues: liveRows.map { ($0.id, $0) })
        return frozenRows.map { latest[$0.id] ?? $0 }
    }

    private var processPlaceholder: String {
        guard let processes = reading.processes,
              processSort == .memory || processes.cpuMeasured else { return "Measuring…" }
        return processSort == .cpu ? "Nothing is busy right now." : "No processes could be measured."
    }

    private func processValue(_ usage: ProcessUsage) -> String {
        switch processSort {
        case .cpu: return usage.cpu.map { String(format: "%.1f%%", $0) } ?? "…"
        case .memory: return bytes(usage.memoryBytes)
        }
    }

    private func quit(_ usage: ProcessUsage) {
        guard AppQuitter.quit(usage) else {
            quitError = "\(usage.name) couldn't be asked to quit. Try Activity Monitor."
            return
        }
        quitError = nil
        quitRequests[usage.id] = Date()
    }

    /// A quit that an app answers with a save dialog leaves it running, so the
    /// button comes back after a while instead of staying stuck on "Quitting".
    private func forgetSettledQuitRequests(now: Date) {
        guard !quitRequests.isEmpty else { return }
        let listed = Set((reading.processes?.byCPU ?? []).map(\.id) + (reading.processes?.byMemory ?? []).map(\.id))
        quitRequests = quitRequests.filter { id, requested in
            listed.contains(id) && now.timeIntervalSince(requested) < 10
        }
    }

    private func metric(_ title: String, value: String, detail: String, color: Color,
                        key: KeyPath<SystemReading, Double?>, maximum: Double = 100) -> some View {
        panel {
            Text(title).font(.sectionHeader).foregroundStyle(Theme.primary)
                .accessibilityAddTraits(.isHeader)
            Text(value)
                .font(.system(size: 20, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail).font(.rowSubtitle).foregroundStyle(Theme.secondary)
            Chart {
                ForEach(Array(monitor.history.enumerated()), id: \.offset) { index, sample in
                    if let value = sample[keyPath: key] {
                        LineMark(x: .value("Time", sample.date), y: .value(title, value),
                                 series: .value("Segment", segment(at: index, key: key)))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }
            .chartYScale(domain: 0...max(1, maximum))
            .chartXScale(domain: reading.date.addingTimeInterval(-120)...reading.date)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
            .accessibilityLabel("\(title) history, current value \(value)")
        }
    }

    private func segment(at index: Int, key: KeyPath<SystemReading, Double?>) -> Int {
        monitor.history.prefix(index).filter { $0[keyPath: key] == nil }.count
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .font(.rowSubtitle)
            .foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .groupSurface()
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.rowSubtitle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
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

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory

    var id: Self { self }
    var title: String { self == .cpu ? "CPU" : "Memory" }
}

private struct ProcessRow: View {
    let usage: ProcessUsage
    let value: String
    let quittable: Bool
    let isQuitting: Bool
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ProcessIcon(bundlePath: usage.bundlePath)
                VStack(alignment: .leading, spacing: 1) {
                    Text(usage.name)
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if usage.processIDs.count > 1 {
                        Text("\(usage.processIDs.count) processes")
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
            }
            .accessibilityElement(children: .combine)
            // A fixed slot keeps the figures aligned whether or not a row can be quit.
            Group {
                if isQuitting {
                    Text("Quitting…").foregroundStyle(Theme.secondary)
                } else if quittable {
                    Button("Quit", action: quit)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Quit \(usage.name)")
                        .help("Ask \(usage.name) to quit")
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: 64, height: 22, alignment: .trailing)
        }
        .frame(minHeight: 30)
    }
}

private struct ProcessIcon: View {
    let bundlePath: String?

    var body: some View {
        Group {
            if let bundlePath {
                Image(nsImage: AppIconCache.icon(for: bundlePath))
                    .resizable()
            } else {
                Image(systemName: "gearshape")
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// The list re-renders every two seconds, and asking Launch Services for an
/// icon each time would redo the same disk lookups.
@MainActor
private enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for bundlePath: String) -> NSImage {
        if let icon = icons[bundlePath] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icons[bundlePath] = icon
        return icon
    }
}
