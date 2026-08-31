import AppKit
import CoreAudio
import Darwin

/// macOS tracks which application a helper process is doing work on behalf of.
/// Apple exports the lookup without shipping a public header for it.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsiblePID(for pid: pid_t) -> pid_t

/// One app that currently owns one or more Core Audio process objects.
struct AudioApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    /// Browsers commonly play through helper processes, so a visible app can
    /// own several Core Audio process objects.
    let processObjectIDs: [AudioObjectID]
    var isPlaying: Bool

    var id: String { bundleID }

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.bundleID == rhs.bundleID
            && lhs.processObjectIDs == rhs.processObjectIDs
            && lhs.isPlaying == rhs.isPlaying
    }
}

enum AppAudioError: LocalizedError {
    case noOutputDevice
    case unsupportedOutputDevice
    case setupFailed

    var errorDescription: String? {
        switch self {
        case .noOutputDevice:
            return "No active audio output device was found."
        case .unsupportedOutputDevice:
            return "Per-app volume is unavailable for the current audio output device."
        case .setupFailed:
            return "macOS could not start per-app audio. Allow System Audio Recording access, then try again."
        }
    }
}

/// Core Audio has no per-process volume property. To provide one, Switchboard
/// taps only the selected app's stream for the current output device, mutes the
/// app's direct path while that tap is read, and renders the same samples back
/// to the device with a gain applied.
///
/// A failed renderer would silence the selected app, so setup validates the
/// tap and aggregate-device formats before starting, and every teardown stops
/// reading the tap before releasing its Core Audio objects.
final class AppAudioEngine {
    /// A small lock-free box for the only value touched by the real-time audio
    /// callback. Swift Dictionary and locks are both inappropriate there.
    private final class AtomicGain {
        private let bits: UnsafeMutablePointer<Int32>

        init(_ value: Float) {
            bits = .allocate(capacity: 1)
            bits.initialize(to: Int32(bitPattern: value.bitPattern))
        }

        func load() -> Float {
            let value = OSAtomicAdd32Barrier(0, bits)
            return Float(bitPattern: UInt32(bitPattern: value))
        }

        func store(_ value: Float) {
            let replacement = Int32(bitPattern: value.bitPattern)
            var current = OSAtomicAdd32Barrier(0, bits)
            while current != replacement,
                  !OSAtomicCompareAndSwap32Barrier(current, replacement, bits) {
                current = OSAtomicAdd32Barrier(0, bits)
            }
        }

        deinit {
            bits.deinitialize(count: 1)
            bits.deallocate()
        }
    }

    private struct PCMFormat: Equatable {
        let sampleRate: Double
        let formatID: AudioFormatID
        let flags: AudioFormatFlags
        let bytesPerPacket: UInt32
        let framesPerPacket: UInt32
        let bytesPerFrame: UInt32
        let channelsPerFrame: UInt32
        let bitsPerChannel: UInt32

        init(_ value: AudioStreamBasicDescription) {
            sampleRate = value.mSampleRate
            formatID = value.mFormatID
            flags = value.mFormatFlags
            bytesPerPacket = value.mBytesPerPacket
            framesPerPacket = value.mFramesPerPacket
            bytesPerFrame = value.mBytesPerFrame
            channelsPerFrame = value.mChannelsPerFrame
            bitsPerChannel = value.mBitsPerChannel
        }

        var isSupported: Bool {
            let isFloat = flags & kAudioFormatFlagIsFloat != 0
            let isPacked = flags & kAudioFormatFlagIsPacked != 0
            let isBigEndian = flags & kAudioFormatFlagIsBigEndian != 0
            let isNonInterleaved = flags & kAudioFormatFlagIsNonInterleaved != 0
            let expectedBytes = UInt32(MemoryLayout<Float>.size)
                * (isNonInterleaved ? 1 : channelsPerFrame)

            return sampleRate > 0
                && formatID == kAudioFormatLinearPCM
                && isFloat && isPacked && !isBigEndian
                && framesPerPacket == 1
                && bitsPerChannel == 32
                && channelsPerFrame > 0
                && bytesPerFrame == expectedBytes
                && bytesPerPacket == bytesPerFrame
        }
    }

    private struct OutputRoute: Equatable {
        let deviceID: AudioDeviceID
        let deviceUID: String
        let streamID: AudioStreamID
        let streamIndex: Int
        let format: PCMFormat
    }

    private struct Aggregate {
        let id: AudioDeviceID
        let uid: String
    }

    private struct Controlled {
        let processObjectIDs: [AudioObjectID]
        let route: OutputRoute
        let gain: AtomicGain
        let tapID: AudioObjectID
        let aggregate: Aggregate
        let ioProcID: AudioDeviceIOProcID
    }

    private struct PendingTeardown {
        let aggregate: Aggregate
        let tapID: AudioObjectID
    }

    private var controlled: [String: Controlled] = [:]
    /// Main-thread state used by the UI. The real-time callback never reads it.
    private var requestedGains: [String: Float] = [:]
    private var pendingTeardowns: [PendingTeardown] = []
    private var teardownTimer: Timer?

    // MARK: - Enumeration

    static func runningApps() -> [AudioApp] {
        var byBundle: [String: (processes: Set<AudioObjectID>, playing: Bool)] = [:]

        for object in objectList(
            AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList,
            scope: kAudioObjectPropertyScopeGlobal
        ) {
            guard let rawBundle = string(object, kAudioProcessPropertyBundleID),
                  !rawBundle.isEmpty,
                  let processID = pid(object),
                  let app = owningApplication(pid: processID, bundleID: rawBundle) else {
                continue
            }
            let key = app.bundleIdentifier ?? rawBundle
            guard key != Bundle.main.bundleIdentifier else { continue }

            let playing = flag(object, kAudioProcessPropertyIsRunningOutput) ?? false
            var entry = byBundle[key] ?? (processes: [], playing: false)
            entry.processes.insert(object)
            entry.playing = entry.playing || playing
            byBundle[key] = entry
        }

        return byBundle.compactMap { key, entry -> AudioApp? in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: key).first,
                  app.activationPolicy == .regular,
                  let name = app.localizedName else {
                return nil
            }
            return AudioApp(
                bundleID: key,
                name: name,
                icon: app.icon,
                processObjectIDs: entry.processes.sorted(),
                isPlaying: entry.playing
            )
        }
        .sorted {
            ($0.isPlaying ? 0 : 1, $0.name.localizedLowercase)
                < ($1.isPlaying ? 0 : 1, $1.name.localizedLowercase)
        }
    }

    /// Maps a helper process back to the regular app a person recognises.
    ///
    /// Chrome names its helpers after the browser, so trimming the bundle ID
    /// reaches the parent. Safari plays through WebKit framework processes
    /// instead, and `com.apple.WebKit.GPU` never trims down to
    /// `com.apple.Safari`, so ask macOS which app the helper answers to before
    /// falling back to the name.
    private static func owningApplication(pid: pid_t, bundleID: String) -> NSRunningApplication? {
        if let direct = NSRunningApplication(processIdentifier: pid),
           direct.activationPolicy == .regular {
            return direct
        }

        let responsible = responsiblePID(for: pid)
        if responsible > 0, responsible != pid,
           let owner = NSRunningApplication(processIdentifier: responsible),
           owner.activationPolicy == .regular {
            return owner
        }

        var candidate = bundleID
        while let dot = candidate.lastIndex(of: ".") {
            candidate = String(candidate[candidate.startIndex..<dot])
            if let parent = NSRunningApplication.runningApplications(withBundleIdentifier: candidate).first,
               parent.activationPolicy == .regular {
                return parent
            }
        }
        return nil
    }

    // MARK: - Gain

    func gain(for bundleID: String) -> Float {
        requestedGains[bundleID] ?? 1
    }

    /// A gain of 1 releases the app back to the normal system mixer.
    func setGain(_ gain: Float, for app: AudioApp) -> Result<Void, AppAudioError> {
        let clamped = max(0, min(1, gain))
        requestedGains[app.bundleID] = clamped

        guard clamped < 1 else {
            release(app.bundleID)
            requestedGains[app.bundleID] = 1
            return .success(())
        }

        if let existing = controlled[app.bundleID],
           existing.processObjectIDs == app.processObjectIDs {
            existing.gain.store(clamped)
            return .success(())
        }

        release(app.bundleID)
        do {
            let route = try Self.defaultOutputRoute()
            controlled[app.bundleID] = try install(app, gain: clamped, route: route)
            return .success(())
        } catch let error as AppAudioError {
            requestedGains[app.bundleID] = 1
            return .failure(error)
        } catch {
            requestedGains[app.bundleID] = 1
            return .failure(.setupFailed)
        }
    }

    /// Rebuilds controls when an app's helpers or the default output device
    /// change. This is also what releases taps after an app quits while the
    /// Switchboard panel is closed.
    func reconcile(with apps: [AudioApp]) -> [String] {
        guard !controlled.isEmpty else { return [] }
        let current = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })
        let route = try? Self.defaultOutputRoute()
        var failures: [String] = []

        for bundleID in Array(controlled.keys) {
            guard let app = current[bundleID] else {
                release(bundleID)
                requestedGains.removeValue(forKey: bundleID)
                continue
            }
            guard let existing = controlled[bundleID] else { continue }
            guard existing.processObjectIDs != app.processObjectIDs || existing.route != route else {
                continue
            }

            let gain = requestedGains[bundleID] ?? 1
            release(bundleID)
            guard gain < 1 else { continue }
            guard let route else {
                requestedGains[bundleID] = 1
                failures.append("\(app.name): \(AppAudioError.noOutputDevice.localizedDescription)")
                continue
            }
            do {
                controlled[bundleID] = try install(app, gain: gain, route: route)
            } catch let error as AppAudioError {
                requestedGains[bundleID] = 1
                failures.append("\(app.name): \(error.localizedDescription)")
            } catch {
                requestedGains[bundleID] = 1
                failures.append("\(app.name): \(AppAudioError.setupFailed.localizedDescription)")
            }
        }
        return failures
    }

    func releaseAll() {
        for bundleID in Array(controlled.keys) {
            release(bundleID)
        }
        requestedGains.removeAll()
    }

    var isControllingAnything: Bool { !controlled.isEmpty }

    // MARK: - Tap and aggregate device

    private func install(_ app: AudioApp, gain: Float, route: OutputRoute) throws -> Controlled {
        guard !app.processObjectIDs.isEmpty else { throw AppAudioError.setupFailed }

        // Device-bound taps capture only streams destined for this output, and
        // Core Audio guarantees that their format matches the chosen stream.
        let description = CATapDescription(
            processes: app.processObjectIDs,
            deviceUID: route.deviceUID,
            stream: UInt(route.streamIndex)
        )
        description.name = "Switchboard \(app.name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
              tapID != kAudioObjectUnknown else {
            throw AppAudioError.setupFailed
        }

        guard let tapUID = Self.string(tapID, kAudioTapPropertyUID),
              let tapFormat = Self.audioFormat(tapID, selector: kAudioTapPropertyFormat),
              tapFormat.isSupported,
              tapFormat == route.format else {
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw AppAudioError.unsupportedOutputDevice
        }

        let aggregate: Aggregate
        do {
            aggregate = try Self.createAggregate(
                named: "Switchboard \(app.name)",
                outputUID: route.deviceUID,
                tapUID: tapUID
            )
        } catch {
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw error
        }

        guard Self.aggregateFormatsMatch(aggregate.id, expected: route.format) else {
            beginTeardown(aggregate: aggregate, tapID: tapID)
            throw AppAudioError.unsupportedOutputDevice
        }

        let gainState = AtomicGain(gain)
        var ioProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregate.id,
            nil
        ) { _, input, _, output, _ in
            Self.render(input: input, output: output, gain: gainState.load())
        }
        guard createStatus == noErr, let ioProcID else {
            beginTeardown(aggregate: aggregate, tapID: tapID)
            throw AppAudioError.setupFailed
        }

        let startStatus = AudioDeviceStart(aggregate.id, ioProcID)
        guard startStatus == noErr else {
            _ = AudioDeviceDestroyIOProcID(aggregate.id, ioProcID)
            beginTeardown(aggregate: aggregate, tapID: tapID)
            throw AppAudioError.setupFailed
        }

        return Controlled(
            processObjectIDs: app.processObjectIDs,
            route: route,
            gain: gainState,
            tapID: tapID,
            aggregate: aggregate,
            ioProcID: ioProcID
        )
    }

    private func release(_ bundleID: String) {
        guard let control = controlled.removeValue(forKey: bundleID) else { return }
        // If Core Audio refuses a stop during a device transition, the live
        // renderer still falls back to normal volume instead of leaving the
        // selected app attenuated.
        control.gain.store(1)
        _ = AudioDeviceStop(control.aggregate.id, control.ioProcID)
        _ = AudioDeviceDestroyIOProcID(control.aggregate.id, control.ioProcID)
        beginTeardown(aggregate: control.aggregate, tapID: control.tapID)
    }

    /// Aggregate destruction is asynchronous. Keep the tap alive until the
    /// aggregate with the matching UID has actually disappeared, then destroy
    /// the tap and stop polling once Core Audio confirms both are gone.
    private func beginTeardown(aggregate: Aggregate, tapID: AudioObjectID) {
        _ = AudioHardwareDestroyAggregateDevice(aggregate.id)
        pendingTeardowns.append(PendingTeardown(aggregate: aggregate, tapID: tapID))
        guard teardownTimer == nil else { return }

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollTeardowns()
        }
        RunLoop.main.add(timer, forMode: .common)
        teardownTimer = timer
    }

    private func pollTeardowns() {
        pendingTeardowns = pendingTeardowns.filter { pending in
            if Self.string(pending.aggregate.id, kAudioDevicePropertyDeviceUID) == pending.aggregate.uid {
                _ = AudioHardwareDestroyAggregateDevice(pending.aggregate.id)
                return true
            }

            let status = AudioHardwareDestroyProcessTap(pending.tapID)
            return status != noErr && Self.objectExists(pending.tapID)
        }

        if pendingTeardowns.isEmpty {
            teardownTimer?.invalidate()
            teardownTimer = nil
        }
    }

    /// Input and output were validated as the same Float32 PCM format. Buffer
    /// shape is checked again for each callback before touching sample memory.
    private static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        gain: Float
    ) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: input)
        )
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)

        for buffer in outputBuffers {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
        guard inputBuffers.count == outputBuffers.count else { return }

        for index in inputBuffers.indices {
            let inputBuffer = inputBuffers[index]
            let outputBuffer = outputBuffers[index]
            guard inputBuffer.mNumberChannels == outputBuffer.mNumberChannels,
                  inputBuffer.mDataByteSize == outputBuffer.mDataByteSize,
                  inputBuffer.mDataByteSize % UInt32(MemoryLayout<Float>.size) == 0,
                  let sourceData = inputBuffer.mData,
                  let destinationData = outputBuffer.mData else {
                continue
            }

            let sampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let source = sourceData.assumingMemoryBound(to: Float.self)
            let destination = destinationData.assumingMemoryBound(to: Float.self)
            for sample in 0..<sampleCount {
                destination[sample] = source[sample] * gain
            }
        }
    }

    private static func createAggregate(
        named name: String,
        outputUID: String,
        tapUID: String
    ) throws -> Aggregate {
        let uid = "com.Mehul72.switchboard.\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUID
            ]]
        ]

        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else {
            throw AppAudioError.setupFailed
        }
        return Aggregate(id: deviceID, uid: uid)
    }

    // MARK: - Core Audio property helpers

    private static func defaultOutputRoute() throws -> OutputRoute {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr,
        deviceID != kAudioObjectUnknown,
        flag(deviceID, kAudioDevicePropertyDeviceIsAlive) == true,
        let uid = string(deviceID, kAudioDevicePropertyDeviceUID) else {
            throw AppAudioError.noOutputDevice
        }

        let streams = objectList(
            deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput
        )
        // A device-bound tap targets one stream. Supporting several physical
        // streams would require a mixer and channel routing rather than a copy.
        guard streams.count == 1,
              let format = audioFormat(streams[0], selector: kAudioStreamPropertyVirtualFormat),
              format.isSupported else {
            throw AppAudioError.unsupportedOutputDevice
        }

        return OutputRoute(
            deviceID: deviceID,
            deviceUID: uid,
            streamID: streams[0],
            streamIndex: 0,
            format: format
        )
    }

    private static func aggregateFormatsMatch(_ deviceID: AudioDeviceID, expected: PCMFormat) -> Bool {
        let inputs = objectList(
            deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeInput
        )
        let outputs = objectList(
            deviceID,
            selector: kAudioDevicePropertyStreams,
            scope: kAudioDevicePropertyScopeOutput
        )
        guard inputs.count == 1, outputs.count == 1,
              let input = audioFormat(inputs[0], selector: kAudioStreamPropertyVirtualFormat),
              let output = audioFormat(outputs[0], selector: kAudioStreamPropertyVirtualFormat) else {
            return false
        }
        return input == expected && output == expected
    }

    private static func objectList(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }

        var values = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values) == noErr else {
            return []
        }
        return values
    }

    private static func audioFormat(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> PCMFormat? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return PCMFormat(value)
    }

    private static func string(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            return nil
        }
        return value as String
    }

    private static func pid(_ object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<pid_t>.size)
        var value: pid_t = 0
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func flag(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    private static func objectExists(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioClassID(0)
        var size = UInt32(MemoryLayout<AudioClassID>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    deinit {
        teardownTimer?.invalidate()
        releaseAll()
    }
}
