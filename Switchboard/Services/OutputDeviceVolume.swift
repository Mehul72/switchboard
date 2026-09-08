import AudioToolbox
import CoreAudio
import Foundation

enum OutputVolumeState: Equatable {
    case available(Float, writable: Bool)
    case unsupported
    case unavailable(String)
}

enum OutputVolumeError: LocalizedError {
    case deviceUnavailable
    case unsupported
    case invalidVolume
    case hardware(OSStatus)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "The output device is no longer available."
        case .unsupported: return "This device does not allow volume changes from macOS. Use its own controls."
        case .invalidVolume: return "The output volume must be between 0% and 100%."
        case .hardware(let status): return "macOS could not access the output volume (error \(status)). Try again."
        }
    }
}

struct OutputVolumeControl {
    let deviceID: AudioDeviceID
    let selector: AudioObjectPropertySelector
}

protocol OutputVolumeAccess {
    func control(for uid: String) throws -> OutputVolumeControl?
    func isWritable(_ control: OutputVolumeControl) throws -> Bool
    func read(_ control: OutputVolumeControl) throws -> Float
    func write(_ value: Float, to control: OutputVolumeControl) throws
}

struct OutputDeviceVolume {
    private let access: any OutputVolumeAccess

    init(access: any OutputVolumeAccess = CoreAudioOutputVolumeAccess()) {
        self.access = access
    }

    func read(uid: String) throws -> OutputVolumeState {
        guard let control = try access.control(for: uid) else { return .unsupported }
        let value = try access.read(control)
        guard value.isFinite, (0...1).contains(value) else { throw OutputVolumeError.invalidVolume }
        return .available(value, writable: try access.isWritable(control))
    }

    func set(_ value: Float, uid: String) throws {
        guard value.isFinite, (0...1).contains(value) else { throw OutputVolumeError.invalidVolume }
        // Resolve the persistent UID on every write because HAL object IDs can change after reconnection.
        guard let control = try access.control(for: uid), try access.isWritable(control) else {
            throw OutputVolumeError.unsupported
        }
        try access.write(value, to: control)
    }
}

struct CoreAudioOutputVolumeAccess: OutputVolumeAccess {
    func control(for uid: String) throws -> OutputVolumeControl? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try withUnsafePointer(to: &qualifier) { pointer in
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<CFString>.size), pointer, &size, &deviceID))
        }
        guard deviceID != kAudioObjectUnknown else { throw OutputVolumeError.deviceUnavailable }
        // The virtual main control preserves balance on devices with separate channel controls.
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            let control = OutputVolumeControl(deviceID: deviceID, selector: selector)
            var address = volumeAddress(control)
            if AudioObjectHasProperty(deviceID, &address) { return control }
        }
        return nil
    }

    func isWritable(_ control: OutputVolumeControl) throws -> Bool {
        var address = volumeAddress(control)
        var writable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(control.deviceID, &address, &writable))
        return writable.boolValue
    }

    func read(_ control: OutputVolumeControl) throws -> Float {
        var address = volumeAddress(control)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        try check(AudioObjectGetPropertyData(control.deviceID, &address, 0, nil, &size, &value))
        return value
    }

    func write(_ value: Float, to control: OutputVolumeControl) throws {
        var address = volumeAddress(control)
        var value = value
        try check(AudioObjectSetPropertyData(control.deviceID, &address, 0, nil,
                                            UInt32(MemoryLayout<Float32>.size), &value))
    }

    private func volumeAddress(_ control: OutputVolumeControl) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: control.selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw OutputVolumeError.hardware(status) }
    }
}
