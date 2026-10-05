import XCTest

@MainActor
final class MenuBarReadoutTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    func testOffByDefault() {
        XCTAssertTrue(MenuBarReadout(defaults: defaults).metrics.isEmpty)
    }

    func testChoicesPersistInDisplayOrder() {
        let readout = MenuBarReadout(defaults: defaults)
        readout.setShown(.battery, true)
        readout.setShown(.cpu, true)
        readout.setShown(.network, true)
        readout.setShown(.network, false)
        readout.setShown(.cpu, true)
        XCTAssertEqual(readout.metrics, [.cpu, .battery])
        XCTAssertEqual(MenuBarReadout(defaults: defaults).metrics, [.cpu, .battery])
    }

    func testUnknownStoredMetricsAreIgnored() {
        defaults.set(["gpu", "fan-speed", "cpu", "cpu"], forKey: MenuBarReadout.defaultsKey)
        XCTAssertEqual(MenuBarReadout(defaults: defaults).metrics, [.cpu, .gpu])
    }

    private func reading(cpu: Double? = 12.4, gpu: Double? = 3, memoryUsed: Double? = 16e9,
                         received: Double = 1.5 * 1024 * 1024, sent: Double = 30 * 1024,
                         charge: Double? = 82, powerState: String = "On battery") -> SystemReading {
        var reading = SystemReading()
        reading.cpu = cpu
        reading.gpu = gpu
        reading.memoryUsed = memoryUsed
        reading.memoryTotal = 32e9
        reading.network = NetworkRate(received: received, sent: sent)
        reading.power = PowerReading(charge: charge, state: powerState)
        return reading
    }

    func testTextShowsEachChosenMetric() {
        XCTAssertEqual(ReadoutFormat.text(for: reading(), metrics: ReadoutMetric.allCases),
                       "CPU  12%  GPU   3%  MEM  50%  ↓1.5M ↑ 30K  BAT  82%")
        XCTAssertEqual(ReadoutFormat.text(for: reading(), metrics: []), "")
    }

    func testMissingValuesKeepTheirPlace() {
        var empty = reading(cpu: nil, gpu: nil, memoryUsed: nil, charge: nil)
        empty.network = nil
        XCTAssertEqual(ReadoutFormat.text(for: empty, metrics: ReadoutMetric.allCases),
                       "CPU  --%  GPU  --%  MEM  --%  ↓  -- ↑  --  BAT  --%")
    }

    func testBatteryIsLeftOutOnAMacWithoutOne() {
        let desktop = reading(charge: nil, powerState: PowerReading().state)
        XCTAssertEqual(ReadoutFormat.text(for: desktop, metrics: [.cpu, .battery]), "CPU  12%")
        XCTAssertEqual(ReadoutFormat.spoken(for: desktop, metrics: [.battery]), "")
    }

    func testPercentsAreClampedAndRounded() {
        XCTAssertEqual(ReadoutFormat.percent(0), "  0%")
        XCTAssertEqual(ReadoutFormat.percent(99.5), "100%")
        XCTAssertEqual(ReadoutFormat.percent(140), "100%")
        XCTAssertEqual(ReadoutFormat.percent(-3), "  0%")
        XCTAssertEqual(ReadoutFormat.percent(.nan), " --%")
    }

    func testRatesStepThroughUnitsWithoutGrowing() {
        XCTAssertEqual(ReadoutFormat.rate(0), "0.0K")
        XCTAssertEqual(ReadoutFormat.rate(400), "0.4K")
        XCTAssertEqual(ReadoutFormat.rate(12 * 1024), " 12K")
        XCTAssertEqual(ReadoutFormat.rate(999 * 1024), "999K")
        // 999.6K would round to "1000K", five characters.
        XCTAssertEqual(ReadoutFormat.rate(999.6 * 1024), "1.0M")
        XCTAssertEqual(ReadoutFormat.rate(1.5 * 1024 * 1024), "1.5M")
        XCTAssertEqual(ReadoutFormat.rate(3 * 1024 * 1024 * 1024), "3.0G")
        XCTAssertEqual(ReadoutFormat.rate(-1), "  --")
        XCTAssertEqual(ReadoutFormat.rate(.infinity), "  --")
        XCTAssertEqual(ReadoutFormat.rate(9e18), "999T", "past the largest unit it pins rather than widening")
    }

    /// The whole point of the padding: any reading produces the same number of
    /// characters, so a monospaced menu bar item never changes width.
    func testTextLengthNeverChangesWithTheFigures() {
        let percents: [Double?] = [nil, 0, 4.4, 9.6, 55, 99.9, 100, 250]
        let rates: [Double] = [0, 1, 900, 10_000, 1_023_487, 1_048_576, 5e8, 7e11, 3e12]
        let expected = ReadoutFormat.text(for: reading(), metrics: ReadoutMetric.allCases).count
        for percent in percents {
            for rate in rates {
                let text = ReadoutFormat.text(for: reading(cpu: percent, gpu: percent, memoryUsed: percent.map { $0 * 3.2e8 },
                                                           received: rate, sent: rate, charge: percent),
                                              metrics: ReadoutMetric.allCases)
                XCTAssertEqual(text.count, expected, text)
            }
        }
    }

    func testSpokenTextNamesEveryFigure() {
        XCTAssertEqual(ReadoutFormat.spoken(for: reading(), metrics: [.cpu, .memory, .network, .battery]),
                       "CPU 12 percent, memory 50 percent, download 1.5 MB per second, upload 30 KB per second, battery 82 percent")
        XCTAssertEqual(ReadoutFormat.spoken(for: reading(cpu: nil), metrics: [.cpu]), "CPU unavailable")
    }
}
