import Combine
import Darwin
import Foundation
import IOKit
import IOKit.ps
import OSLog

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: CPUTicks) -> Double? {
        let busy = Double(user &- previous.user) + Double(system &- previous.system)
            + Double(nice &- previous.nice)
        let total = busy + Double(idle &- previous.idle)
        return total > 0 ? busy / total * 100 : nil
    }
}

struct NetworkCounter {
    let received: UInt64
    let sent: UInt64
}

struct NetworkRate {
    let received: Double
    let sent: Double

    static func measure(current: [String: NetworkCounter], previous: [String: NetworkCounter],
                        elapsed: TimeInterval) -> NetworkRate? {
        guard elapsed > 0, elapsed.isFinite else { return nil }
        var received = 0.0
        var sent = 0.0
        for (name, counter) in current {
            guard let old = previous[name] else { continue }
            // Interface counters can reset when a connection is re-established.
            if counter.received >= old.received { received += Double(counter.received - old.received) }
            if counter.sent >= old.sent { sent += Double(counter.sent - old.sent) }
        }
        return NetworkRate(received: received / elapsed, sent: sent / elapsed)
    }
}

struct PowerReading {
    var charge: Double?
    var state = "No battery"
    var minutesRemaining: Int?
    var cycles: Int?
    var temperature: Double?
    var watts: Double?
}

struct SystemReading {
    var date = Date()
    var cpu: Double?
    var gpu: Double?
    var memoryUsed: Double?
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var swapUsed: Double?
    var network: NetworkRate?
    var diskFree: Double?
    var diskTotal: Double?
    var power = PowerReading()
    var thermalState = ProcessInfo.processInfo.thermalState
    var unavailable: [String] = []
}

// Sampling and resets share one serial queue; no mutable state escapes the reader.
final class SystemMetricsReader: @unchecked Sendable {
    private var previousCPU: CPUTicks?
    private var previousNetwork: [String: NetworkCounter]?
    private var previousTime: TimeInterval?
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "SystemMonitor")
    private var reportedFailures = Set<String>()

    func reset() {
        previousCPU = nil
        previousNetwork = nil
        previousTime = nil
    }

    func read() -> SystemReading {
        var reading = SystemReading()
        let time = ProcessInfo.processInfo.systemUptime
        if let ticks = cpuTicks() {
            reading.cpu = previousCPU.flatMap { ticks.usage(since: $0) }
            previousCPU = ticks
        } else {
            previousCPU = nil
            reading.unavailable.append("CPU")
        }
        reading.memoryUsed = memoryUsed()
        reading.swapUsed = swapUsed()
        if reading.memoryUsed == nil { reading.unavailable.append("Memory") }
        if reading.swapUsed == nil { reading.unavailable.append("Swap") }
        if let counters = networkCounters() {
            if let previousNetwork, let previousTime {
                reading.network = NetworkRate.measure(current: counters, previous: previousNetwork,
                                                      elapsed: time - previousTime)
            }
            previousNetwork = counters
            previousTime = time
        } else {
            previousNetwork = nil
            previousTime = nil
            reading.unavailable.append("Network")
        }
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
                forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            reading.diskFree = values.volumeAvailableCapacity.map(Double.init)
            reading.diskTotal = values.volumeTotalCapacity.map(Double.init)
        } catch {
            reading.unavailable.append("Disk")
        }
        reading.gpu = gpuUsage()
        reading.power = powerReading()
        let failures = Set(reading.unavailable)
        for failure in failures.subtracting(reportedFailures) {
            logger.error("System metric unavailable: \(failure, privacy: .public)")
        }
        reportedFailures = failures
        return reading
    }

    private func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
    }

    private func memoryUsed() -> Double? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // File-backed pages are reclaimable cache, not application memory.
        let pages = max(0, Double(info.active_count) + Double(info.inactive_count)
                        + Double(info.wire_count) + Double(info.compressor_page_count)
                        - Double(info.external_page_count) - Double(info.purgeable_count))
        return min(Double(ProcessInfo.processInfo.physicalMemory), pages * Double(vm_kernel_page_size))
    }

    private func swapUsed() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Double(usage.xsu_used)
    }

    private func networkCounters() -> [String: NetworkCounter]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var result: [String: NetworkCounter] = [:]
        var cursor = addresses
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let interface = entry.pointee
            guard let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = interface.ifa_data else { continue }
            let name = String(cString: interface.ifa_name)
            // Physical Ethernet/Wi-Fi interfaces avoid counting VPN and bridge traffic twice.
            guard name.hasPrefix("en") else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = NetworkCounter(received: UInt64(counters.ifi_ibytes), sent: UInt64(counters.ifi_obytes))
        }
        return result
    }

    private func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
                == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue()
                    as? [String: Any],
                  let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue,
                  value.isFinite, (0...100).contains(value) else { continue }
            values.append(value)
        }
        return values.max()
    }

    private func powerReading() -> PowerReading {
        var result = PowerReading()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            result.state = "Power information unavailable"
            return result
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            if let current = description[kIOPSCurrentCapacityKey] as? Double,
               let max = description[kIOPSMaxCapacityKey] as? Double, max > 0 {
                result.charge = min(100, Swift.max(0, current / max * 100))
            }
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            result.state = charging ? "Charging" : (pluggedIn ? "Power adapter" : "On battery")
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = description[key] as? Int, minutes > 0 { result.minutesRemaining = minutes }
        }
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard battery != 0 else { return result }
        defer { IOObjectRelease(battery) }
        func number(_ key: String) -> Double? {
            (IORegistryEntryCreateCFProperty(battery, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.doubleValue
        }
        result.cycles = number("CycleCount").map(Int.init)
        if let temperature = number("Temperature"), temperature > 0 {
            result.temperature = temperature / 100
        }
        if let voltage = number("Voltage"), let amperage = number("InstantAmperage") {
            // Some drivers expose a negative signed current as an unsigned 64-bit number.
            let signedCurrent = amperage > Double(Int64.max) ? amperage - pow(2, 64) : amperage
            let watts = abs(voltage * signedCurrent) / 1_000_000
            if watts.isFinite, watts < 1000 { result.watts = watts }
        }
        return result
    }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var reading = SystemReading()
    @Published private(set) var history: [SystemReading] = []
    @Published private(set) var isRunning = false
    private let queue = DispatchQueue(label: "com.Mehul72.switchboard.monitor", qos: .utility)
    private let reader = SystemMetricsReader()
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    static let historyLimit = 60

    func start() {
        guard timer == nil else { return }
        isRunning = true
        generation = UUID()
        let currentGeneration = generation
        history.removeAll(keepingCapacity: true)
        reading = SystemReading()
        queue.async { [reader] in reader.reset() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self, reader] in
            let reading = reader.read()
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.generation == currentGeneration else { return }
                self.reading = reading
                self.history.append(reading)
                if self.history.count > Self.historyLimit {
                    self.history.removeFirst(self.history.count - Self.historyLimit)
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        generation = UUID()
    }

    deinit { timer?.cancel() }
}
