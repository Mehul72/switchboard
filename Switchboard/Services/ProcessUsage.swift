import AppKit
import Darwin
import Foundation
import OSLog

/// One row in the System tab's "Using the most" list: an app with all of its
/// helper processes, or a single process that is not part of an app.
struct ProcessUsage: Identifiable, Equatable {
    /// The app bundle's path, or `pid:<n>` for a process outside any app.
    let id: String
    let name: String
    let bundlePath: String?
    let processIDs: [pid_t]
    /// Percent of every core's time, so the rows add up to the CPU tile.
    /// Nil until two samples exist.
    let cpu: Double?
    let memoryBytes: Double
    /// True when at least one process belongs to this account. Processes run
    /// by macOS or another user can be listed but never quit from here.
    let isOwnedByUser: Bool
}

struct TopProcesses: Equatable {
    var byCPU: [ProcessUsage] = []
    var byMemory: [ProcessUsage] = []
    /// False on the first sample, when no CPU time has been measured yet.
    var cpuMeasured = false

    static let rowLimit = 5

    static func rank(_ samples: [ProcessSample], cpuMeasured: Bool, limit: Int = rowLimit,
                     bundleName: (String) -> String) -> TopProcesses {
        var groups: [String: [ProcessSample]] = [:]
        var order: [String] = []
        for sample in samples {
            let key = ProcessGrouping.appBundlePath(forExecutable: sample.executablePath) ?? "pid:\(sample.pid)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(sample)
        }
        let usages = order.compactMap { key -> ProcessUsage? in
            guard let members = groups[key], let first = members.first else { return nil }
            let bundlePath = key.hasPrefix("pid:") ? nil : key
            let shares = members.compactMap(\.cpuShare)
            return ProcessUsage(
                id: key,
                name: bundlePath.map(bundleName) ?? ProcessGrouping.processName(forExecutable: first.executablePath,
                                                                               pid: first.pid),
                bundlePath: bundlePath,
                processIDs: members.map(\.pid).sorted(),
                cpu: cpuMeasured && !shares.isEmpty ? min(100, shares.reduce(0, +)) : nil,
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                isOwnedByUser: members.contains(where: \.isOwnedByUser))
        }
        // Ties break on name so equal rows do not swap places every sample.
        let byCPU = usages.filter { ($0.cpu ?? 0) > 0 }
            .sorted { ($0.cpu ?? 0, $1.name) > ($1.cpu ?? 0, $0.name) }
        let byMemory = usages.filter { $0.memoryBytes > 0 }
            .sorted { ($0.memoryBytes, $1.name) > ($1.memoryBytes, $0.name) }
        return TopProcesses(byCPU: Array(byCPU.prefix(limit)), byMemory: Array(byMemory.prefix(limit)),
                            cpuMeasured: cpuMeasured)
    }
}

/// One process as measured in a single sample.
struct ProcessSample: Equatable {
    let pid: pid_t
    let executablePath: String
    /// Percent of every core's time since the previous sample.
    let cpuShare: Double?
    let memoryBytes: Double
    let isOwnedByUser: Bool
}

enum ProcessGrouping {
    /// The outermost app bundle holding an executable, so helper apps nested
    /// inside a browser count toward the browser.
    static func appBundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func processName(forExecutable path: String, pid: pid_t) -> String {
        // ps puts names it cannot resolve to a path in parentheses.
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let name = (trimmed as NSString).lastPathComponent
        return name.isEmpty ? "Process \(pid)" : name
    }
}

/// Process CPU time is counted in Mach ticks on Apple silicon and in
/// nanoseconds on Intel. The host timebase converts either to nanoseconds.
struct CPUClock: Equatable {
    let numerator: UInt32
    let denominator: UInt32

    static let host: CPUClock = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else {
            return CPUClock(numerator: 1, denominator: 1)
        }
        return CPUClock(numerator: info.numer, denominator: info.denom)
    }()

    func seconds(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(numerator) / Double(denominator) / 1_000_000_000
    }
}

/// Cumulative CPU time of one process, tagged with its start time so a
/// recycled process ID is never compared with the process it replaced.
struct ProcessCPUTime: Equatable {
    let startTicks: UInt64
    let cpuTicks: UInt64

    func share(since previous: ProcessCPUTime, elapsedSeconds: Double, cores: Int,
               clock: CPUClock) -> Double? {
        guard startTicks == previous.startTicks, cpuTicks >= previous.cpuTicks,
              elapsedSeconds > 0, elapsedSeconds.isFinite, cores > 0 else { return nil }
        let busySeconds = clock.seconds(fromTicks: cpuTicks - previous.cpuTicks)
        return min(100, busySeconds / (elapsedSeconds * Double(cores)) * 100)
    }
}

/// Rows from `ps`, which is setuid root and so can report processes that
/// this account is not allowed to inspect directly.
enum ProcessStatusTable {
    struct Row: Equatable {
        let pid: pid_t
        /// Activity Monitor style: 100 means one whole core.
        let cpuPercentOfOneCore: Double
        let residentBytes: Double
        let path: String
    }

    static let arguments = ["-axo", "pid=,pcpu=,rss=,comm="]

    static func parse(_ output: String) -> [pid_t: Row] {
        var rows: [pid_t: Row] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = pid_t(fields[0]), pid > 0,
                  let cpu = Double(fields[1]), cpu.isFinite, cpu >= 0,
                  let residentKilobytes = Double(fields[2]), residentKilobytes >= 0 else { continue }
            rows[pid] = Row(pid: pid, cpuPercentOfOneCore: cpu, residentBytes: residentKilobytes * 1024,
                            path: fields[3].trimmingCharacters(in: .whitespaces))
        }
        return rows
    }

    enum Failure: Error, Equatable { case launch, timedOut, exitStatus(Int32) }

    /// Runs `ps` once. A stuck `ps` would hold up every later sample on the
    /// monitor's queue, so it is killed after `timeout`.
    static func read(timeout: TimeInterval = 2) -> Result<[pid_t: Row], Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        // A comma decimal separator would make every CPU figure unparseable.
        process.environment = ["LC_ALL": "C"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failure(.launch)
        }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        // Read before waiting: the listing is larger than the pipe buffer.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit else { return .failure(.timedOut) }
        guard process.terminationStatus == 0 else { return .failure(.exitStatus(process.terminationStatus)) }
        return .success(parse(String(decoding: data, as: UTF8.self)))
    }
}

/// Measures every process on each call. Not thread safe: the monitor calls it
/// from its own serial queue only.
final class ProcessSampler {
    private struct Known {
        let time: ProcessCPUTime
        let path: String
    }

    private var previous: [pid_t: Known] = [:]
    private var previousUptime: TimeInterval?
    private var bundleNames: [String: String] = [:]
    private var lastStatusFailure: ProcessStatusTable.Failure?
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "SystemMonitor")
    private let clock: CPUClock
    private let cores: Int

    init(clock: CPUClock = .host, cores: Int = ProcessInfo.processInfo.activeProcessorCount) {
        self.clock = clock
        self.cores = max(1, cores)
    }

    func reset() {
        previous = [:]
        previousUptime = nil
    }

    /// The ranked list, plus the names of sources that could not be read.
    func sample() -> (top: TopProcesses, unavailable: [String]) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let elapsed = previousUptime.map { uptime - $0 }
        guard let pids = Self.allProcessIDs() else {
            reset()
            return (TopProcesses(), ["Processes"])
        }
        var current: [pid_t: Known] = [:]
        var samples: [ProcessSample] = []
        var othersPIDs: [pid_t] = []
        for pid in pids {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else {
                if errno == EPERM { othersPIDs.append(pid) }
                continue
            }
            let time = ProcessCPUTime(startTicks: info.ri_proc_start_abstime,
                                      cpuTicks: info.ri_user_time &+ info.ri_system_time)
            let known = previous[pid]
            let path: String
            if let known, known.time.startTicks == time.startTicks {
                path = known.path
            } else {
                path = Self.path(of: pid)
            }
            current[pid] = Known(time: time, path: path)
            let share = known.flatMap { old in
                elapsed.flatMap { time.share(since: old.time, elapsedSeconds: $0, cores: cores, clock: clock) }
            }
            samples.append(ProcessSample(pid: pid, executablePath: path, cpuShare: share,
                                         memoryBytes: Double(info.ri_phys_footprint), isOwnedByUser: true))
        }
        var unavailable: [String] = []
        if !othersPIDs.isEmpty {
            switch ProcessStatusTable.read() {
            case .success(let rows):
                lastStatusFailure = nil
                for pid in othersPIDs {
                    guard let row = rows[pid] else { continue }
                    samples.append(ProcessSample(pid: pid, executablePath: row.path,
                                                 cpuShare: min(100, row.cpuPercentOfOneCore / Double(cores)),
                                                 memoryBytes: row.residentBytes, isOwnedByUser: false))
                }
            case .failure(let failure):
                // The monitor only logs that the source is unavailable; the
                // reason is here, once per change so a stuck ps does not flood the log.
                if failure != lastStatusFailure {
                    logger.error("ps failed: \(String(describing: failure), privacy: .public)")
                    lastStatusFailure = failure
                }
                unavailable.append("System processes")
            }
        }
        previous = current
        previousUptime = uptime
        let top = TopProcesses.rank(samples, cpuMeasured: elapsed != nil) { [self] path in bundleName(path) }
        return (top, unavailable)
    }

    private func bundleName(_ path: String) -> String {
        if let cached = bundleNames[path] { return cached }
        let display = FileManager.default.displayName(atPath: path)
        let name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        bundleNames[path] = name
        return name
    }

    private static func allProcessIDs() -> [pid_t]? {
        var capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return nil }
        // Processes can start between sizing and listing, so leave headroom
        // and retry if the buffer still came back full.
        for _ in 0..<3 {
            capacity += 64
            var pids = [pid_t](repeating: 0, count: capacity)
            let filled = pids.withUnsafeMutableBufferPointer {
                proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
            }
            guard filled > 0 else { return nil }
            if Int(filled) < capacity { return pids.prefix(Int(filled)).filter { $0 > 0 } }
            capacity *= 2
        }
        return nil
    }

    private static func path(of pid: pid_t) -> String {
        // PROC_PIDPATHINFO_MAXSIZE is a C macro Swift does not import.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }
}

/// Quitting from the process list goes through the same request the Dock
/// sends, so apps can still ask about unsaved work.
@MainActor
enum AppQuitter {
    /// The app a row represents, if it is one Switchboard is willing to quit.
    static func quittableApp(for usage: ProcessUsage) -> NSRunningApplication? {
        guard usage.isOwnedByUser, usage.bundlePath != nil else { return nil }
        return usage.processIDs.lazy
            .compactMap { NSRunningApplication(processIdentifier: $0) }
            .first(where: isQuittable)
    }

    static func isQuittable(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated,
              app.activationPolicy != .prohibited,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.finder" else { return false }
        // Dock, Control Center, loginwindow and friends live here; quitting
        // them only makes macOS restart them, or ends the session.
        return !(app.bundleURL?.path.contains("/System/Library/") ?? true)
    }

    static func quit(_ usage: ProcessUsage) -> Bool {
        quittableApp(for: usage)?.terminate() ?? false
    }
}
