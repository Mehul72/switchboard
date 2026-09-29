import XCTest

/// Stands in for macOS: which holds are taken, what powers the Mac, which apps
/// run, and the callbacks the controller registers for changes.
private final class FakeMac {
    struct Hold { let token = NSObject(); let allowsDisplaySleep: Bool }

    var holds: [Hold] = []
    var refusesHolds = false
    var power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: true)
    var running: Set<pid_t> = []
    var powerChanged: (() -> Void)?
    var appExited: ((pid_t) -> Void)?
    var powerNotificationsWork = true

    /// Clears the callback when the controller lets go of its watcher.
    final class Token {
        private let release: () -> Void
        init(_ release: @escaping () -> Void) { self.release = release }
        deinit { release() }
    }

    lazy var environment = AwakeEnvironment(
        beginHold: { [unowned self] allowDisplaySleep in
            guard !self.refusesHolds else { return nil }
            let hold = Hold(allowsDisplaySleep: allowDisplaySleep)
            self.holds.append(hold)
            return hold.token
        },
        endHold: { [unowned self] token in self.holds.removeAll { $0.token === token } },
        power: { [unowned self] in self.power },
        isRunning: { [unowned self] pid in self.running.contains(pid) },
        observePower: { [unowned self] callback in
            guard self.powerNotificationsWork else { return nil }
            self.powerChanged = callback
            return Token { [weak self] in self?.powerChanged = nil }
        },
        observeExits: { [unowned self] callback in
            self.appExited = callback
            return Token { [weak self] in self?.appExited = nil }
        }
    )
}

final class AwakeControllerTests: XCTestCase {
    private var mac: FakeMac!
    private var controller: AwakeController!
    private var finishes: [AwakeFinish] = []

    override func setUp() {
        super.setUp()
        mac = FakeMac()
        controller = AwakeController(environment: mac.environment)
        controller.onFinish = { [unowned self] in self.finishes.append($0) }
    }

    override func tearDown() {
        controller = nil
        XCTAssertTrue(mac.holds.isEmpty, "a released controller must not leave the Mac held awake")
        mac = nil
        super.tearDown()
    }

    private func succeeds(_ mode: AwakeMode, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let failure) = controller.set(mode) {
            XCTFail("\(mode) failed: \(failure)", file: file, line: line)
        }
    }

    private func failure(starting mode: AwakeMode) -> AwakeStartFailure? {
        guard case .failure(let failure) = controller.set(mode) else { return nil }
        return failure
    }

    // MARK: - Durations

    func testTimedModeHoldsAndReportsItsEnd() throws {
        succeeds(.minutes(30))
        XCTAssertEqual(mac.holds.count, 1)
        XCTAssertFalse(try XCTUnwrap(mac.holds.first).allowsDisplaySleep)
        let endsAt = try XCTUnwrap(controller.span?.endsAt)
        XCTAssertEqual(endsAt.timeIntervalSinceNow, 1800, accuracy: 5)
        succeeds(.off)
        XCTAssertTrue(mac.holds.isEmpty)
        XCTAssertNil(controller.span)
    }

    func testInvalidDurationLeavesTheCurrentModeAlone() {
        succeeds(.untilStopped)
        XCTAssertEqual(failure(starting: .minutes(0)), .invalidDuration)
        XCTAssertEqual(failure(starting: .minutes(-5)), .invalidDuration)
        XCTAssertEqual(controller.mode, .untilStopped)
        XCTAssertEqual(mac.holds.count, 1)
        succeeds(.off)
    }

    func testChangingModeKeepsOneHoldAndTheOriginalStartTime() throws {
        succeeds(.untilStopped)
        let started = try XCTUnwrap(controller.span?.startedAt)
        succeeds(.minutes(60))
        mac.running = [42]
        succeeds(.untilAppQuits(pid: 42, name: "Xcode"))
        XCTAssertEqual(mac.holds.count, 1)
        XCTAssertEqual(controller.span?.startedAt, started)
        succeeds(.off)
    }

    func testRefusedAssertionLeavesKeepAwakeOff() {
        mac.refusesHolds = true
        XCTAssertEqual(failure(starting: .untilStopped), .assertionRefused)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - Until an app quits

    func testEndsWhenTheChosenAppQuitsAndNotBefore() {
        mac.running = [42]
        succeeds(.untilAppQuits(pid: 42, name: "Xcode"))
        XCTAssertEqual(controller.span?.condition, .appRuns(name: "Xcode"))
        mac.appExited?(7)
        XCTAssertTrue(controller.isHolding, "another app quitting must not end it")
        mac.appExited?(42)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertTrue(mac.holds.isEmpty)
        XCTAssertEqual(finishes, [.appQuit(name: "Xcode")])
        XCTAssertNil(mac.appExited, "the exit watcher is released once it has done its job")
    }

    func testAnAppThatAlreadyQuitIsRefusedAndReleasesAnyHold() {
        succeeds(.untilStopped)
        XCTAssertEqual(failure(starting: .untilAppQuits(pid: 42, name: "Xcode")), .appNotRunning)
        XCTAssertEqual(controller.mode, .off)
        XCTAssertTrue(mac.holds.isEmpty)
        XCTAssertNil(mac.appExited)
        XCTAssertTrue(finishes.isEmpty, "a refused start is reported by set, not as a finish")
    }

    func testSwitchingAwayStopsWatchingTheApp() {
        mac.running = [42]
        succeeds(.untilAppQuits(pid: 42, name: "Xcode"))
        succeeds(.minutes(30))
        XCTAssertNil(mac.appExited)
        XCTAssertTrue(controller.isHolding)
        succeeds(.off)
    }

    // MARK: - While plugged in

    func testFollowsThePowerAdapter() {
        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: false)
        succeeds(.whilePluggedIn)
        XCTAssertTrue(controller.isActive)
        XCTAssertFalse(controller.isHolding, "on battery it waits instead of draining it")
        XCTAssertEqual(controller.span?.condition, .pluggedIn(holding: false))

        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: true)
        mac.powerChanged?()
        XCTAssertEqual(mac.holds.count, 1)
        XCTAssertEqual(controller.span?.condition, .pluggedIn(holding: true))
        // Charge-level updates arrive through the same notification.
        mac.powerChanged?()
        XCTAssertEqual(mac.holds.count, 1)

        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: false)
        mac.powerChanged?()
        XCTAssertTrue(mac.holds.isEmpty)
        XCTAssertEqual(controller.mode, .whilePluggedIn)
        XCTAssertTrue(finishes.isEmpty, "unplugging pauses; it does not end the mode")

        succeeds(.off)
        XCTAssertNil(mac.powerChanged)
    }

    func testPowerChangesThatMoveTheHoldAreReported() {
        var changes = 0
        controller.onHoldChange = { changes += 1 }
        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: false)
        succeeds(.whilePluggedIn)
        mac.powerChanged?()
        XCTAssertEqual(changes, 0, "a charge-level update on battery changes nothing")
        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: true)
        mac.powerChanged?()
        mac.powerChanged?()
        XCTAssertEqual(changes, 1)
        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: false)
        mac.powerChanged?()
        XCTAssertEqual(changes, 2)
        succeeds(.off)
    }

    func testUnknownPowerSourceDoesNotHold() {
        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: nil)
        succeeds(.whilePluggedIn)
        XCTAssertFalse(controller.isHolding)
        succeeds(.off)
    }

    func testChoosingItOnBatteryReleasesAnEarlierHold() {
        succeeds(.untilStopped)
        mac.power = PowerSnapshot(hasInternalBattery: true, isOnExternalPower: false)
        succeeds(.whilePluggedIn)
        XCTAssertTrue(mac.holds.isEmpty)
        succeeds(.off)
    }

    func testWithoutPowerNotificationsTheModeIsRefused() {
        mac.powerNotificationsWork = false
        XCTAssertEqual(failure(starting: .whilePluggedIn), .powerChangesUnavailable)
        XCTAssertEqual(controller.mode, .off)
    }

    // MARK: - Display sleep

    func testDisplayOptionSwapsTheHoldAndKeepsTheClock() throws {
        succeeds(.untilStopped)
        let started = try XCTUnwrap(controller.span?.startedAt)
        controller.allowsDisplaySleep = true
        XCTAssertEqual(mac.holds.count, 1)
        XCTAssertTrue(try XCTUnwrap(mac.holds.first).allowsDisplaySleep)
        XCTAssertEqual(controller.span?.startedAt, started)
        controller.allowsDisplaySleep = false
        XCTAssertFalse(try XCTUnwrap(mac.holds.first).allowsDisplaySleep)
        succeeds(.off)
    }

    func testDisplayOptionAppliesToTheNextHold() throws {
        controller.allowsDisplaySleep = true
        XCTAssertTrue(mac.holds.isEmpty)
        succeeds(.minutes(30))
        XCTAssertTrue(try XCTUnwrap(mac.holds.first).allowsDisplaySleep)
        succeeds(.off)
    }

    func testRefusedSwapTurnsKeepAwakeOffRatherThanClaimingItIsOn() {
        succeeds(.untilStopped)
        mac.refusesHolds = true
        controller.allowsDisplaySleep = true
        XCTAssertEqual(controller.mode, .off)
        XCTAssertTrue(mac.holds.isEmpty)
    }
}
