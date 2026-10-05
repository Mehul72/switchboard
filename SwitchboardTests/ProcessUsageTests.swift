import XCTest

final class ProcessUsageTests: XCTestCase {
    private struct FakeApp: Equatable {
        let name: String
        let bundlePath: String?
    }

    /// Asking a browser's helper to quit closes a tab. The row's own bundle
    /// is the app the Quit button is about.
    @MainActor
    func testQuitGoesToTheAppThatOwnsTheBundleNotTheFirstHelper() {
        let helper = FakeApp(name: "helper", bundlePath: "/Applications/Browser.app/Contents/Helpers/Helper.app")
        let browser = FakeApp(name: "browser", bundlePath: "/Applications/Browser.app")

        XCTAssertEqual(AppQuitter.appToQuit(among: [helper, browser], bundlePath: "/Applications/Browser.app",
                                            pathOf: \.bundlePath), browser)
    }

    @MainActor
    func testQuitFallsBackToTheFirstAppWhenNoBundleMatches() {
        let first = FakeApp(name: "first", bundlePath: nil)
        let second = FakeApp(name: "second", bundlePath: "/Elsewhere.app")

        XCTAssertEqual(AppQuitter.appToQuit(among: [first, second], bundlePath: "/Applications/Browser.app",
                                            pathOf: \.bundlePath), first)
        XCTAssertNil(AppQuitter.appToQuit(among: [FakeApp](), bundlePath: "/Applications/Browser.app",
                                          pathOf: \.bundlePath))
    }

    private func sample(_ pid: pid_t, _ path: String, cpu: Double? = nil, memory: Double = 0,
                        mine: Bool = true) -> ProcessSample {
        ProcessSample(pid: pid, executablePath: path, cpuShare: cpu, memoryBytes: memory, isOwnedByUser: mine)
    }

    private func rank(_ samples: [ProcessSample], measured: Bool = true, limit: Int = 5) -> TopProcesses {
        TopProcesses.rank(samples, cpuMeasured: measured, limit: limit) { path in
            ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
    }

    // MARK: - Grouping

    func testHelpersNestedInsideAnAppCountTowardTheOutermostBundle() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/"
            + "Versions/140/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
        XCTAssertEqual(ProcessGrouping.appBundlePath(forExecutable: helper), "/Applications/Google Chrome.app")
        XCTAssertEqual(ProcessGrouping.appBundlePath(forExecutable: "/System/Applications/Music.app/Contents/MacOS/Music"),
                       "/System/Applications/Music.app")
    }

    func testProcessesOutsideAnAppAreNotGrouped() {
        XCTAssertNil(ProcessGrouping.appBundlePath(forExecutable: "/usr/local/bin/node"))
        XCTAssertNil(ProcessGrouping.appBundlePath(forExecutable: ""))
        // Only a real bundle component counts, not a name that merely contains ".app".
        XCTAssertNil(ProcessGrouping.appBundlePath(forExecutable: "/Users/me/my.application/run"))
        XCTAssertNil(ProcessGrouping.appBundlePath(forExecutable: "/Users/me/Notes.app.backup/run"))
    }

    func testProcessNamesComeFromThePathAndNeverReadBlank() {
        XCTAssertEqual(ProcessGrouping.processName(forExecutable: "/usr/local/bin/node", pid: 7), "node")
        XCTAssertEqual(ProcessGrouping.processName(forExecutable: "(docker)", pid: 7), "docker")
        XCTAssertEqual(ProcessGrouping.processName(forExecutable: "", pid: 7), "Process 7")
    }

    func testRankSumsAnAppsProcessesAndSortsEachList() {
        let top = rank([
            sample(10, "/Applications/Browser.app/Contents/MacOS/Browser", cpu: 5, memory: 400),
            sample(11, "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
                   cpu: 10, memory: 600),
            sample(20, "/usr/local/bin/node", cpu: 12, memory: 100),
            sample(30, "/System/Library/CoreServices/WindowServer", cpu: 1, memory: 900, mine: false)
        ])
        XCTAssertEqual(top.byCPU.map(\.name), ["Browser", "node", "WindowServer"])
        XCTAssertEqual(top.byCPU.first?.cpu, 15)
        XCTAssertEqual(top.byCPU.first?.processIDs, [10, 11])
        XCTAssertEqual(top.byCPU.first?.bundlePath, "/Applications/Browser.app")
        XCTAssertEqual(top.byMemory.map(\.name), ["Browser", "WindowServer", "node"])
        XCTAssertEqual(top.byMemory.first?.memoryBytes, 1000)
        XCTAssertEqual(top.byCPU.first(where: { $0.name == "node" })?.id, "pid:20")
        XCTAssertFalse(try XCTUnwrap(top.byMemory.first { $0.name == "WindowServer" }).isOwnedByUser)
    }

    /// The first sample has no CPU time to compare with. Showing only ps rows
    /// (which arrive with a figure already) would crown system processes for
    /// two seconds, so the CPU list stays empty until everyone is measured.
    func testFirstSampleListsMemoryButNoCPU() {
        let top = rank([sample(1, "/bin/a", cpu: 50, memory: 10, mine: false), sample(2, "/bin/b", memory: 20)],
                       measured: false)
        XCTAssertFalse(top.cpuMeasured)
        XCTAssertTrue(top.byCPU.isEmpty)
        XCTAssertEqual(top.byMemory.map(\.name), ["b", "a"])
    }

    func testIdleProcessesAreLeftOutOfTheCPUList() {
        let top = rank([sample(1, "/bin/idle", cpu: 0, memory: 5), sample(2, "/bin/new", memory: 5)])
        XCTAssertTrue(top.byCPU.isEmpty)
        XCTAssertEqual(top.byMemory.count, 2)
    }

    func testRankHonoursTheLimitAndBreaksTiesByName() {
        let samples = (1...8).map { sample(pid_t($0), "/bin/p\(9 - $0)", cpu: 2, memory: 7) }
        let top = rank(samples, limit: 3)
        XCTAssertEqual(top.byCPU.map(\.name), ["p1", "p2", "p3"])
        XCTAssertEqual(top.byMemory.map(\.name), ["p1", "p2", "p3"])
    }

    func testAppCPUNeverExceedsTheWholeMac() {
        let top = rank((1...3).map { sample(pid_t($0), "/Applications/Hot.app/Contents/MacOS/p\($0)", cpu: 60) })
        XCTAssertEqual(top.byCPU.first?.cpu, 100)
    }

    func testEmptySampleRanksToEmptyLists() {
        let top = rank([])
        XCTAssertTrue(top.byCPU.isEmpty)
        XCTAssertTrue(top.byMemory.isEmpty)
    }

    // MARK: - CPU time

    /// Measured on an M-series Mac: one busy second is 24M ticks, timebase 125/3.
    func testAppleSiliconTicksConvertToSeconds() {
        let clock = CPUClock(numerator: 125, denominator: 3)
        XCTAssertEqual(clock.seconds(fromTicks: 24_000_000), 1, accuracy: 1e-9)
        XCTAssertEqual(CPUClock(numerator: 1, denominator: 1).seconds(fromTicks: 2_000_000_000), 2)
    }

    func testShareIsAPortionOfAllCores() {
        let clock = CPUClock(numerator: 1, denominator: 1)
        let before = ProcessCPUTime(startTicks: 5, cpuTicks: 1_000_000_000)
        let after = ProcessCPUTime(startTicks: 5, cpuTicks: 3_000_000_000)
        // Two busy seconds over two wall seconds is one full core: a quarter of four cores.
        XCTAssertEqual(after.share(since: before, elapsedSeconds: 2, cores: 4, clock: clock), 25)
        XCTAssertEqual(after.share(since: before, elapsedSeconds: 0.5, cores: 1, clock: clock), 100)
    }

    func testRecycledProcessIDIsNotComparedWithItsPredecessor() {
        let clock = CPUClock(numerator: 1, denominator: 1)
        let old = ProcessCPUTime(startTicks: 5, cpuTicks: 1_000)
        let reused = ProcessCPUTime(startTicks: 9, cpuTicks: 9_000_000_000)
        XCTAssertNil(reused.share(since: old, elapsedSeconds: 2, cores: 4, clock: clock))
    }

    func testImpossibleIntervalsProduceNoShare() {
        let clock = CPUClock(numerator: 1, denominator: 1)
        let before = ProcessCPUTime(startTicks: 5, cpuTicks: 2_000)
        let after = ProcessCPUTime(startTicks: 5, cpuTicks: 1_000)
        XCTAssertNil(after.share(since: before, elapsedSeconds: 2, cores: 4, clock: clock))
        XCTAssertNil(before.share(since: after, elapsedSeconds: 0, cores: 4, clock: clock))
        XCTAssertNil(before.share(since: after, elapsedSeconds: .nan, cores: 4, clock: clock))
        XCTAssertNil(before.share(since: after, elapsedSeconds: 2, cores: 0, clock: clock))
    }

    // MARK: - ps

    func testParsesPathsWithSpacesAndSkipsJunk() {
        let output = """
          414   5.0 121472 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
          686   1.9 520320 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
         3354   2.9  26496 (docker)
        garbage line
            7  abc    100 /bin/x
            8   1.0     -5 /bin/y
            0   1.0    100 /bin/kernel
        """
        let rows = ProcessStatusTable.parse(output)
        XCTAssertEqual(rows.keys.sorted(), [414, 686, 3354])
        XCTAssertEqual(rows[686]?.path, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
        XCTAssertEqual(rows[686]?.residentBytes, 520_320 * 1024)
        XCTAssertEqual(rows[414]?.cpuPercentOfOneCore, 5)
        XCTAssertEqual(rows[3354]?.path, "(docker)")
        XCTAssertTrue(ProcessStatusTable.parse("").isEmpty)
    }

    func testLivePSListsSystemProcesses() throws {
        let rows = try ProcessStatusTable.read().get()
        XCTAssertNotNil(rows[1], "launchd is always pid 1")
        XCTAssertNotNil(rows[getpid()])
    }

    // MARK: - Live sampler

    func testLiveSamplerMeasuresThisProcessOnTheSecondSample() throws {
        let sampler = ProcessSampler()
        let first = sampler.sample()
        XCTAssertFalse(first.top.cpuMeasured)
        XCTAssertFalse(first.top.byMemory.isEmpty)
        // Burn CPU so this test process has something to show.
        let deadline = Date().addingTimeInterval(0.3)
        var spin = 0.0
        while Date() < deadline { spin += sin(spin) + 1 }
        XCTAssertGreaterThan(spin, 0)
        let second = sampler.sample()
        XCTAssertTrue(second.top.cpuMeasured)
        XCTAssertTrue(second.unavailable.isEmpty, "\(second.unavailable)")
        let busiest = try XCTUnwrap(second.top.byCPU.first?.cpu)
        XCTAssertGreaterThan(busiest, 0)
        XCTAssertLessThanOrEqual(busiest, 100)
        sampler.reset()
        XCTAssertFalse(sampler.sample().top.cpuMeasured)
    }
}
