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
