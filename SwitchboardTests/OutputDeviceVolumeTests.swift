import CoreAudio
import XCTest

final class OutputDeviceVolumeTests: XCTestCase {
    func testReadsCurrentHardwareVolumeAndWriteCapability() throws {
        let hardware = VolumeHardwareStub()
        let volume = OutputDeviceVolume(access: hardware)
        XCTAssertEqual(try volume.read(uid: "speakers"), .available(0.4, writable: true))
        hardware.value = 0.7
        hardware.writable = false
        XCTAssertEqual(try volume.read(uid: "speakers"), .available(0.7, writable: false))
    }

    func testDeviceWithoutVolumeControlIsUnsupportedAndCannotBeWritten() throws {
        let hardware = VolumeHardwareStub()
        hardware.hasControl = false
        let volume = OutputDeviceVolume(access: hardware)
        XCTAssertEqual(try volume.read(uid: "hdmi"), .unsupported)
        XCTAssertThrowsError(try volume.set(0.5, uid: "hdmi"))
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    func testReadOnlyDeviceCannotBeWritten() {
        let hardware = VolumeHardwareStub()
        hardware.writable = false
        XCTAssertThrowsError(try OutputDeviceVolume(access: hardware).set(0.5, uid: "speakers"))
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    func testRejectsInvalidLevelsBeforeAccessingHardware() {
        let hardware = VolumeHardwareStub()
        let volume = OutputDeviceVolume(access: hardware)
        for value: Float in [-0.1, 1.1, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try volume.set(value, uid: "speakers"))
        }
        XCTAssertTrue(hardware.requestedUIDs.isEmpty)
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    func testZeroFullAndRepeatedWritesAreAccepted() throws {
        let hardware = VolumeHardwareStub()
        let volume = OutputDeviceVolume(access: hardware)
        for value: Float in [0, 1, 0.5, 0.5] { try volume.set(value, uid: "speakers") }
        XCTAssertEqual(hardware.writes.map(\.value), [0, 1, 0.5, 0.5])
        XCTAssertEqual(try volume.read(uid: "speakers"), .available(0.5, writable: true))
    }

    func testReconnectResolvesTheUIDAgainInsteadOfWritingToOldObject() throws {
        let hardware = VolumeHardwareStub()
        let volume = OutputDeviceVolume(access: hardware)
        try volume.set(0.3, uid: "headphones")
        hardware.deviceID = 99
        try volume.set(0.6, uid: "headphones")
        XCTAssertEqual(hardware.requestedUIDs, ["headphones", "headphones"])
        XCTAssertEqual(hardware.writes.map(\.deviceID), [42, 99])
    }

    func testReadAndWriteFailuresArePropagated() {
        let hardware = VolumeHardwareStub()
        hardware.fails = true
        let volume = OutputDeviceVolume(access: hardware)
        XCTAssertThrowsError(try volume.read(uid: "speakers"))
        XCTAssertThrowsError(try volume.set(0.5, uid: "speakers"))
        XCTAssertEqual(hardware.value, 0.4)
    }

    func testInvalidHardwareReadingsAreNotShownAsRealVolumes() {
        let hardware = VolumeHardwareStub()
        for value: Float in [.nan, .infinity, -1, 2] {
            hardware.value = value
            XCTAssertThrowsError(try OutputDeviceVolume(access: hardware).read(uid: "speakers"))
        }
    }

    func testMissingDeviceDoesNotFallBackToSystemDefault() {
        let volume = OutputDeviceVolume()
        let missingUID = "switchboard.tests.missing.\(UUID().uuidString)"
        XCTAssertThrowsError(try volume.read(uid: missingUID))
        XCTAssertThrowsError(try volume.set(0.1, uid: missingUID))
    }

    func testConnectedDeviceVolumesCanBeReadWithoutChangingThem() throws {
        let volume = OutputDeviceVolume()
        let devices = AppAudioEngine.outputDevices()
        XCTAssertFalse(devices.isEmpty)
        for device in devices {
            let state = try volume.read(uid: device.uid)
            if case .available(let value, _) = state {
                XCTAssertTrue((0...1).contains(value))
            } else {
                XCTAssertEqual(state, .unsupported)
            }
        }
    }
}

private final class VolumeHardwareStub: OutputVolumeAccess {
    var hasControl = true
    var writable = true
    var value: Float = 0.4
    var deviceID: AudioDeviceID = 42
    var fails = false
    var requestedUIDs: [String] = []
    var writes: [(deviceID: AudioDeviceID, value: Float)] = []

    func control(for uid: String) throws -> OutputVolumeControl? {
        requestedUIDs.append(uid)
        return hasControl ? OutputVolumeControl(deviceID: deviceID, selector: kAudioDevicePropertyVolumeScalar) : nil
    }

    func isWritable(_ control: OutputVolumeControl) throws -> Bool { writable }

    func read(_ control: OutputVolumeControl) throws -> Float {
        if fails { throw OutputVolumeError.hardware(-1) }
        return value
    }

    func write(_ value: Float, to control: OutputVolumeControl) throws {
        if fails { throw OutputVolumeError.hardware(-1) }
        writes.append((control.deviceID, value))
        self.value = value
    }
}
