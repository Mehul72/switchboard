import AppKit
import CoreGraphics
import XCTest
@testable import Switchboard

@MainActor
final class DisplayScalingBackendTests: XCTestCase {
    func testStoppingWithoutSessionIsIdempotent() throws {
        let backend = DisplayScalingBackend()
        try backend.stop()
        try backend.stop()
        XCTAssertFalse(backend.isSessionValid())
    }

    func testRejectsInvalidPresetBeforeChangingDisplays() async throws {
        let backend = DisplayScalingBackend()
        let preset = DisplayScalePreset(id: "invalid", width: Int.max, height: 1440, percent: 100)
        do {
            try await backend.start(displayID: CGMainDisplayID(), preset: preset)
            XCTFail("Invalid allocation sizes must be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("outside the supported range"))
        }
        XCTAssertFalse(backend.isSessionValid())
        try backend.stop()
    }

    func testRejectsDisconnectedDisplay() async throws {
        let backend = DisplayScalingBackend()
        do {
            try await backend.start(displayID: kCGNullDirectDisplay, preset: samplePreset)
            XCTFail("A disconnected display must be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no longer connected"))
        }
        XCTAssertFalse(backend.isSessionValid())
    }

    func testBuiltInDisplayCannotBeScaled() async throws {
        let backend = DisplayScalingBackend()
        guard let builtIn = try backend.displays().first(where: \.isBuiltIn) else {
            throw XCTSkip("This Mac has no connected built-in display")
        }
        XCTAssertNotNil(builtIn.unavailableReason)
        do {
            try await backend.start(displayID: builtIn.id, preset: samplePreset)
            XCTFail("Built-in displays must remain under macOS control")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("built-in"))
        }
        XCTAssertFalse(backend.isSessionValid())
    }

    func testAlreadyCancelledSetupDoesNotCreateSession() async throws {
        let backend = DisplayScalingBackend()
        let preset = samplePreset
        let task = Task { try await backend.start(displayID: CGMainDisplayID(), preset: preset) }
        task.cancel()
        do {
            try await task.value
            XCTFail("Cancelled setup must not run")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(backend.isSessionValid())
    }

    func testBridgeRejectsInvalidAllocationBeforeCreatingDisplay() {
        XCTAssertThrowsError(try SBVirtualDisplay(name: "Invalid", width: 4097, height: 1152, refreshRate: 60))
        XCTAssertThrowsError(try SBVirtualDisplay(name: "Invalid", width: 2752, height: 1152, refreshRate: .nan))
        XCTAssertThrowsError(try SBVirtualDisplay(name: "Invalid", width: 4096, height: 4096, refreshRate: 60))
    }

    private var samplePreset: DisplayScalePreset {
        DisplayScalePreset(id: "2752x1152", width: 2752, height: 1152, percent: 125)
    }

}
