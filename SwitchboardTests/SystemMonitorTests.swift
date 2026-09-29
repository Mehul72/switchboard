import XCTest

final class SystemMonitorTests: XCTestCase {
    func testCPUUsageIncludesSystemAndNiceTime() {
        let previous = CPUTicks(user: 100, system: 50, idle: 200, nice: 0)
        let current = CPUTicks(user: 120, system: 60, idle: 260, nice: 10)
        XCTAssertEqual(current.usage(since: previous), 40)
        XCTAssertNil(current.usage(since: current))
    }

    func testCPUCountersWrapWithoutSpiking() {
        let previous = CPUTicks(user: UInt32.max - 9, system: 0, idle: 10, nice: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 30, nice: 0)
        XCTAssertEqual(current.usage(since: previous), 50)
    }

    func testNetworkUsesElapsedTimeAndIgnoresNewInterfaces() {
        let previous = ["en0": NetworkCounter(received: 100, sent: 50)]
        let current = ["en0": NetworkCounter(received: 500, sent: 150),
                       "en1": NetworkCounter(received: 9000, sent: 9000)]
        let rate = NetworkRate.measure(current: current, previous: previous, elapsed: 2)
        XCTAssertEqual(rate?.received, 200)
        XCTAssertEqual(rate?.sent, 50)
    }

    func testNetworkResetAndDisconnectedInterfaceDoNotSpike() {
        let previous = ["en0": NetworkCounter(received: 1000, sent: 1000),
                        "en1": NetworkCounter(received: 500, sent: 500)]
        let current = ["en0": NetworkCounter(received: 10, sent: 20)]
        let rate = NetworkRate.measure(current: current, previous: previous, elapsed: 2)
        XCTAssertEqual(rate?.received, 0)
        XCTAssertEqual(rate?.sent, 0)
        XCTAssertNil(NetworkRate.measure(current: current, previous: previous, elapsed: 0))
        XCTAssertNil(NetworkRate.measure(current: current, previous: previous, elapsed: -.infinity))
        XCTAssertNil(NetworkRate.measure(current: current, previous: previous, elapsed: .nan))
    }

    func testLiveReaderReturnsPlausibleMemoryAndSwap() throws {
        let reader = SystemMetricsReader()
        let first = reader.read()
        let memory = try XCTUnwrap(first.memoryUsed)
        XCTAssertGreaterThan(memory, 0)
        XCTAssertLessThanOrEqual(memory, first.memoryTotal)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(first.swapUsed), 0)
        XCTAssertNil(first.cpu)
        XCTAssertNil(first.network)
        let next = reader.read()
        if let cpu = next.cpu { XCTAssertTrue((0...100).contains(cpu)) }
        XCTAssertNotNil(next.network)
        reader.reset()
        XCTAssertNil(reader.read().network)
    }

    @MainActor
    func testRepeatedStartAndStopAreSafe() {
        let monitor = SystemMonitor()
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertTrue(monitor.history.isEmpty)
        monitor.stop()
    }
}

/// The menu bar readout keeps the monitor running with the panel closed, and
/// listing every process is too costly to do for a number in the menu bar.
@MainActor
final class SystemMonitorDemandTests: XCTestCase {
    private func waitForReading(_ monitor: SystemMonitor, timeout: TimeInterval = 6,
                                where condition: (SystemReading) -> Bool) async -> SystemReading? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !monitor.history.isEmpty, condition(monitor.reading) { return monitor.reading }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    func testMenuBarAloneSamplesWithoutProcesses() async throws {
        let monitor = SystemMonitor()
        defer { monitor.feedsMenuBar = false }
        monitor.feedsMenuBar = true
        XCTAssertTrue(monitor.isRunning)
        let reading = await waitForReading(monitor) { _ in true }
        XCTAssertNotNil(reading)
        XCTAssertNil(reading?.processes)
    }

    func testOpeningThePanelAddsProcessesAndKeepsHistory() async throws {
        let monitor = SystemMonitor()
        defer {
            monitor.stop()
            monitor.feedsMenuBar = false
        }
        monitor.feedsMenuBar = true
        _ = await waitForReading(monitor) { _ in true }
        monitor.start()
        XCTAssertFalse(monitor.history.isEmpty, "opening the panel must not throw away menu bar history")
        let withProcesses = await waitForReading(monitor) { $0.processes != nil }
        let processes = try XCTUnwrap(withProcesses?.processes)
        XCTAssertFalse(processes.byMemory.isEmpty)
        monitor.stop()
        XCTAssertTrue(monitor.isRunning, "the menu bar still needs readings")
        let afterClose = await waitForReading(monitor) { $0.processes == nil }
        XCTAssertNotNil(afterClose)
        monitor.feedsMenuBar = false
        XCTAssertFalse(monitor.isRunning)
    }

    func testClosingThePanelLeavesTheMenuBarRunning() {
        let monitor = SystemMonitor()
        monitor.start()
        monitor.feedsMenuBar = true
        monitor.stop()
        XCTAssertTrue(monitor.isRunning)
        monitor.feedsMenuBar = false
        XCTAssertFalse(monitor.isRunning)
        monitor.feedsMenuBar = false
        XCTAssertFalse(monitor.isRunning)
    }
}
