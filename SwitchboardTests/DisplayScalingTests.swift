import XCTest

final class DisplayScalePresetTests: XCTestCase {
    func testDell125PercentUsesHighResolutionDesktopWithMatchingAspect() throws {
        let preset = try XCTUnwrap(DisplayScalePreset.choices(width: 3440, height: 1440).first { $0.percent == 125 })
        XCTAssertEqual(preset.width, 2752)
        XCTAssertEqual(preset.height, 1152)
        XCTAssertEqual(preset.width * 2, 5504)
        XCTAssertEqual(preset.height * 2, 2304)
        XCTAssertEqual(Double(3440) / Double(preset.width), 1.25)
    }

    func testPresetsStayWithinRenderingBudgetAndRetainAspectRatio() {
        for (width, height) in [(3440, 1440), (5120, 2160), (3840, 2160), (2560, 1440), (1920, 1080)] {
            let presets = DisplayScalePreset.choices(width: width, height: height)
            XCTAssertFalse(presets.isEmpty)
            XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
            for preset in presets {
                XCTAssertTrue(preset.isValid)
                XCTAssertEqual(preset.width % 2, 0)
                XCTAssertEqual(preset.height % 2, 0)
                XCTAssertEqual(Double(preset.width) / Double(preset.height), Double(width) / Double(height), accuracy: 0.004)
            }
        }
    }

    func testInvalidAndOverflowDimensionsAreRejectedBeforeArithmetic() {
        for (width, height) in [(0, 0), (-1, 1440), (3440, 0), (Int.max, Int.max), (799, 600)] {
            XCTAssertTrue(DisplayScalePreset.choices(width: width, height: height).isEmpty)
        }
        XCTAssertFalse(DisplayScalePreset(id: "bad", width: Int.max, height: Int.max, percent: 125).isValid)
    }

    func testSmallDisplaysNeverGetAnUnusableDesktop() {
        XCTAssertEqual(DisplayScalePreset.choices(width: 800, height: 600).map(\.percent), [100])
        XCTAssertFalse(DisplayScalePreset(id: "small", width: 1720, height: 580, percent: 200).isValid)
    }
}

@MainActor
private final class ScalingTestBackend: DisplayScalingBackendProtocol {
    var available = [ScalingDisplay(id: 5, name: "Dell", nativeWidth: 3440, nativeHeight: 1440,
                                   isBuiltIn: false, unavailableReason: nil)]
    var connected = true
    var active = false
    var starts = 0
    var stops = 0
    var failStart = false
    var failStop = false
    var failListing = false
    var suspendStart: CheckedContinuation<Void, Never>?
    var shouldSuspendStart = false
    func displays() throws -> [ScalingDisplay] {
        if failListing { throw DisplayScalingError.unavailable("Display enumeration failed") }
        return connected ? available : []
    }
    func start(displayID: UInt32, preset: DisplayScalePreset) async throws {
        starts += 1
        active = true
        if shouldSuspendStart { await withCheckedContinuation { suspendStart = $0 } }
        try Task.checkCancellation()
        if failStart { throw DisplayScalingError.unavailable("Mode unavailable") }
    }
    func stop() throws {
        stops += 1
        if failStop { throw DisplayScalingError.unavailable("Restore failed") }
        active = false
    }
    func isSessionValid() -> Bool { active && connected }
}

@MainActor
final class DisplayScalingControllerTests: XCTestCase {
    private var backend: ScalingTestBackend!
    private var controller: DisplayScalingController!
    private var clock: TimeInterval = 100

    override func setUp() async throws {
        backend = ScalingTestBackend()
        clock = 100
        controller = DisplayScalingController(backend: backend, now: { [weak self] in self?.clock ?? 0 },
                                              automaticallyTick: false, observeSystem: false)
    }

    override func tearDown() async throws { controller.shutdown() }

    func testDefaultsToDell125PercentAndDoesNotStartUntilRequested() {
        XCTAssertEqual(controller.selectedDisplayID, 5)
        XCTAssertEqual(controller.selectedPreset?.percent, 125)
        XCTAssertTrue(controller.canPreview)
        XCTAssertEqual(backend.starts, 0)
    }

    func testPreviewAutomaticallyRestoresAtDeadline() async {
        await controller.preview()?.value
        XCTAssertEqual(controller.confirmationSeconds, 20)
        clock += 19.1
        controller.tick()
        XCTAssertEqual(controller.confirmationSeconds, 1)
        XCTAssertTrue(backend.active)
        clock += 0.9
        controller.tick()
        XCTAssertFalse(backend.active)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.confirmationSeconds)
    }

    func testKeepCancelsTimeoutButRestoreStillWorks() async {
        await controller.preview()?.value
        controller.keep()
        clock += 100
        controller.tick()
        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.confirmationSeconds)
        controller.restore()
        controller.restore()
        XCTAssertFalse(backend.active)
        XCTAssertNil(controller.errorMessage)
    }

    func testLateKeepCannotSaveAnExpiredPreview() async {
        await controller.preview()?.value
        clock += 20
        controller.keep()
        XCTAssertFalse(backend.active)
    }

    func testClosingPreviewRestoresButClosingConfirmedSessionKeepsIt() async {
        await controller.preview()?.value
        controller.windowWillClose()
        XCTAssertFalse(backend.active)
        await controller.preview()?.value
        controller.keep()
        controller.windowWillClose()
        XCTAssertTrue(backend.active)
    }

    func testStartFailureRestoresPartialSessionAndReportsError() async {
        backend.failStart = true
        await controller.preview()?.value
        XCTAssertFalse(backend.active)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isBusy)
        XCTAssertEqual(controller.errorMessage, "Mode unavailable")
    }

    func testRestoreFailureKeepsRecoveryAvailable() async {
        await controller.preview()?.value
        backend.failStop = true
        controller.restore()
        XCTAssertTrue(controller.isActive)
        XCTAssertNotNil(controller.errorMessage)
        backend.failStop = false
        controller.restore()
        XCTAssertFalse(controller.isActive)
    }

    func testDisconnectStopsConfirmedScalingAndReconnectDoesNotReactivate() async {
        await controller.preview()?.value
        controller.keep()
        backend.connected = false
        controller.displaysDidChange()
        XCTAssertFalse(backend.active)
        XCTAssertTrue(controller.displays.isEmpty)
        backend.connected = true
        controller.displaysDidChange()
        XCTAssertFalse(backend.active)
        XCTAssertEqual(backend.starts, 1)
    }

    func testSleepRestoresConfirmedScaling() async {
        await controller.preview()?.value
        controller.keep()
        controller.prepareForSleep()
        XCTAssertFalse(backend.active)
    }

    func testCancellationDuringStartupCannotActivateLater() async throws {
        backend.shouldSuspendStart = true
        let task = try XCTUnwrap(controller.preview())
        while backend.suspendStart == nil { await Task.yield() }
        XCTAssertNil(controller.preview())
        controller.windowWillClose()
        backend.suspendStart?.resume()
        await task.value
        XCTAssertFalse(backend.active)
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.confirmationSeconds)
        XCTAssertNil(controller.errorMessage)
    }

    func testQuitDuringStartupCannotActivateLater() async throws {
        backend.shouldSuspendStart = true
        let task = try XCTUnwrap(controller.preview())
        while backend.suspendStart == nil { await Task.yield() }
        controller.shutdown()
        backend.suspendStart?.resume()
        await task.value
        XCTAssertFalse(backend.active)
        XCTAssertFalse(controller.canPreview)
    }

    func testNoDisplayBuiltInAndUnsupportedDisplaysDisablePreview() {
        backend.available = []
        controller.refresh()
        XCTAssertFalse(controller.canPreview)
        backend.available = [ScalingDisplay(id: 1, name: "Built-in", nativeWidth: 3024, nativeHeight: 1964,
                                           isBuiltIn: true, unavailableReason: nil)]
        controller.refresh()
        XCTAssertFalse(controller.canPreview)
        backend.available = [ScalingDisplay(id: 2, name: "Mirror", nativeWidth: 3440, nativeHeight: 1440,
                                           isBuiltIn: false, unavailableReason: "Turn off mirroring first")]
        controller.refresh()
        XCTAssertFalse(controller.canPreview)
    }

    func testEnumerationFailureIsVisible() {
        backend.failListing = true
        controller.refresh()
        XCTAssertEqual(controller.errorMessage, "Display enumeration failed")
    }
}
