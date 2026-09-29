import Combine
import Foundation

enum ReadoutMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, battery

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .battery: return "Battery"
        }
    }
}

/// Which System readings sit beside the menu bar icon. Empty, the default,
/// shows none and lets the monitor sleep while the panel is closed.
@MainActor
final class MenuBarReadout: ObservableObject {
    /// Always in `ReadoutMetric.allCases` order, whatever order they were picked in.
    @Published private(set) var metrics: [ReadoutMetric]
    private let defaults: UserDefaults
    static let defaultsKey = "MenuBarReadoutMetrics"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        metrics = ReadoutMetric.allCases.filter { stored.contains($0.rawValue) }
    }

    func isShown(_ metric: ReadoutMetric) -> Bool { metrics.contains(metric) }

    func setShown(_ metric: ReadoutMetric, _ shown: Bool) {
        var chosen = Set(metrics)
        if shown { chosen.insert(metric) } else { chosen.remove(metric) }
        let ordered = ReadoutMetric.allCases.filter(chosen.contains)
        guard ordered != metrics else { return }
        metrics = ordered
        defaults.set(ordered.map(\.rawValue), forKey: Self.defaultsKey)
    }
}

/// Menu bar wording. Every figure is padded to a fixed number of characters
/// and drawn in a monospaced font, so the item keeps one width and the icons
/// beside it do not shuffle every two seconds.
enum ReadoutFormat {
    static func text(for reading: SystemReading, metrics: [ReadoutMetric]) -> String {
        metrics.compactMap { metric -> String? in
            switch metric {
            case .cpu: return "CPU " + percent(reading.cpu)
            case .gpu: return "GPU " + percent(reading.gpu)
            case .memory: return "MEM " + percent(memoryPercent(reading))
            case .network: return "↓" + rate(reading.network?.received) + " ↑" + rate(reading.network?.sent)
            case .battery:
                guard hasBattery(reading) else { return nil }
                return "BAT " + percent(reading.power.charge)
            }
        }
        .joined(separator: "  ")
    }

    /// What VoiceOver reads for the status item.
    static func spoken(for reading: SystemReading, metrics: [ReadoutMetric]) -> String {
        metrics.compactMap { metric -> String? in
            switch metric {
            case .cpu: return "CPU " + spokenPercent(reading.cpu)
            case .gpu: return "GPU " + spokenPercent(reading.gpu)
            case .memory: return "memory " + spokenPercent(memoryPercent(reading))
            case .network:
                return "download " + spokenRate(reading.network?.received)
                    + ", upload " + spokenRate(reading.network?.sent)
            case .battery:
                guard hasBattery(reading) else { return nil }
                return "battery " + spokenPercent(reading.power.charge)
            }
        }
        .joined(separator: ", ")
    }

    /// Three characters and a percent sign: "  5%", " 64%", "100%".
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return padded("--", to: 3) + "%" }
        return padded(String(Int(min(100, max(0, value)).rounded())), to: 3) + "%"
    }

    /// Four characters in binary units, matching the panel: "0.4K", " 12K", "1.2M".
    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return padded("--", to: 4) }
        let units = ["K", "M", "G", "T"]
        var value = bytesPerSecond / 1024
        var unit = 0
        // 999.5 and up would round to four digits, so it moves to the next unit.
        while value >= 999.5, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        value = min(value, 999)
        let number = value < 9.95 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return padded(number + units[unit], to: 4)
    }

    private static func memoryPercent(_ reading: SystemReading) -> Double? {
        guard let used = reading.memoryUsed, reading.memoryTotal > 0 else { return nil }
        return used / reading.memoryTotal * 100
    }

    /// A Mac without a battery says so; any other state still has one, even
    /// when a single read failed.
    private static func hasBattery(_ reading: SystemReading) -> Bool {
        reading.power.charge != nil || reading.power.state != PowerReading().state
    }

    private static func padded(_ text: String, to width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }

    private static func spokenPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "unavailable" }
        return "\(Int(min(100, max(0, value)).rounded())) percent"
    }

    private static func spokenRate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "unavailable" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory) + " per second"
    }
}
