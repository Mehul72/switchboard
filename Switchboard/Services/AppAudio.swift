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

/// One output device an app's audio can be sent to.
struct AudioOutputDevice: Identifiable, Equatable {
    /// Core Audio's own persistent identifier. Names repeat across identical
    /// hardware, so the UID is what a saved route remembers.
    let uid: String
    let name: String

    var id: String { uid }
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

        /// The renderer walks one buffer of interleaved Float samples, so a
        /// non-interleaved tap would have it read every other channel.
        var isInterleavedFloat: Bool {
            isSupported && flags & kAudioFormatFlagIsNonInterleaved == 0
        }
    }

    private struct Aggregate {
        let id: AudioDeviceID
        let uid: String
    }

    /// Counts render callbacks. A tapped app is muted at the source, so a
    /// renderer that stops running leaves it silent with no other symptom;
    /// this is the only signal that the callback is still alive.
    private final class RenderTicks {
        private let count: UnsafeMutablePointer<Int32>

        init() {
            count = .allocate(capacity: 1)
            count.initialize(to: 0)
        }

        func advance() {
            _ = OSAtomicIncrement32Barrier(count)
        }

        func load() -> Int32 {
            OSAtomicAdd32Barrier(0, count)
        }

        deinit {
            count.deinitialize(count: 1)
            count.deallocate()
        }
    }

    private struct Controlled {
        let processObjectIDs: [AudioObjectID]
        /// Where this app is being rendered, which after routing is not
        /// necessarily the system default.
        let deviceUID: String
        let gain: AtomicGain
        let tapID: AudioObjectID
        let aggregate: Aggregate
        let ioProcID: AudioDeviceIOProcID
        let renderTicks: RenderTicks
        /// Watchdog state, compared against `renderTicks` once per maintenance
        /// poll to notice a renderer that has stopped calling back.
        var ticksAtLastPoll: Int32 = 0
        var stalledPolls = 0
    }

    private struct PendingTeardown {
        let aggregate: Aggregate
        let tapID: AudioObjectID
        var polls = 0
    }

    /// Two maintenance polls, so a single missed sample cannot drop a control
    /// that is working.
    private static let stalledPollsBeforeRelease = 2

    private static let teardownPollInterval: TimeInterval = 0.1
    /// Ten seconds of retries. Core Audio finishes an aggregate teardown in a
    /// few polls; a pair of objects it will never reclaim must not leave a
    /// timer running at 10Hz for the rest of the session.
    private static let teardownPollLimit = 100

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

    /// Every device an app's audio can be sent to, in the order a person reads
    /// them.
    static func outputDevices() -> [AudioOutputDevice] {
        objectList(
            AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        .compactMap { deviceID -> AudioOutputDevice? in
            guard let uid = string(deviceID, kAudioDevicePropertyDeviceUID),
                  AudioRouting.isSelectableOutput(
                      uid: uid,
                      isAlive: flag(deviceID, kAudioDevicePropertyDeviceIsAlive) ?? false,
                      hasOutputStreams: !objectList(
                          deviceID,
                          selector: kAudioDevicePropertyStreams,
                          scope: kAudioDevicePropertyScopeOutput
                      ).isEmpty
                  ),
                  let name = string(deviceID, kAudioObjectPropertyName) else {
                return nil
            }
            return AudioOutputDevice(uid: uid, name: name)
        }
        .sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    /// The device macOS is currently sending everything to, or nil when the Mac
    /// has no usable output at all.
    static func systemDefaultOutputUID() -> String? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        return string(deviceID, kAudioDevicePropertyDeviceUID)
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
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

    // MARK: - Volume and routing

    /// Device UIDs chosen per app, kept across launches so an app someone sent
    /// to their speakers goes back there the next time it plays.
    private var requestedRoutes: [String: String] = AppAudioEngine.savedRoutes()

    func gain(for bundleID: String) -> Float {
        requestedGains[bundleID] ?? 1
    }

    /// The device chosen for an app, whether or not it is currently plugged in.
    func selectedOutputUID(for bundleID: String) -> String? {
        requestedRoutes[bundleID]
    }

    /// Full volume is not stored, so an app at 100% on the default output is
    /// one this engine has no opinion about.
    func setGain(_ gain: Float, for app: AudioApp) -> Result<Void, AppAudioError> {
        let clamped = max(0, min(1, gain))
        if AudioRouting.isFullVolume(clamped) {
            requestedGains.removeValue(forKey: app.bundleID)
        } else {
            requestedGains[app.bundleID] = clamped
        }
        return apply(to: app)
    }

    /// Sends an app to one output device, or back to the system default with
    /// `nil`.
    func setOutputDevice(_ uid: String?, for app: AudioApp) -> Result<Void, AppAudioError> {
        if let uid {
            requestedRoutes[app.bundleID] = uid
        } else {
            requestedRoutes.removeValue(forKey: app.bundleID)
        }
        Self.persistRoutes(requestedRoutes)
        return apply(to: app)
    }

    /// Brings one app's tap into line with the volume and device chosen for it.
    private func apply(to app: AudioApp) -> Result<Void, AppAudioError> {
        let gain = requestedGains[app.bundleID] ?? 1
        let selected = requestedRoutes[app.bundleID]
        let systemDefault = Self.systemDefaultOutputUID()
        let effective = AudioRouting.effectiveDeviceUID(
            selected: selected,
            available: Set(Self.outputDevices().map(\.uid)),
            systemDefault: systemDefault
        )

        guard AudioRouting.needsTap(gain: gain, selected: selected,
                                    effective: effective, systemDefault: systemDefault) else {
            release(app.bundleID)
            return .success(())
        }
        guard let effective else {
            forgetRequest(app.bundleID)
            return .failure(.noOutputDevice)
        }

        // A tap already pointed at the right device only needs the new gain,
        // and rebuilding it would drop a moment of the app's audio.
        if let existing = controlled[app.bundleID],
           existing.processObjectIDs == app.processObjectIDs,
           existing.deviceUID == effective {
            existing.gain.store(gain)
            return .success(())
        }

        release(app.bundleID)
        do {
            controlled[app.bundleID] = try install(app, gain: gain, deviceUID: effective)
            return .success(())
        } catch let error as AppAudioError {
            forgetRequest(app.bundleID)
            return .failure(error)
        } catch {
            forgetRequest(app.bundleID)
            return .failure(.setupFailed)
        }
    }

    /// Drops a request nothing is enforcing, so a row never shows a volume or a
    /// device that failed to take effect.
    private func forgetRequest(_ bundleID: String) {
        requestedGains.removeValue(forKey: bundleID)
        if requestedRoutes.removeValue(forKey: bundleID) != nil {
            Self.persistRoutes(requestedRoutes)
        }
    }

    /// Rebuilds controls when an app's helpers change, when the default output
    /// changes under an app that was following it, or when a chosen device is
    /// unplugged; re-applies a choice to an app that stopped and resumed
    /// playing; and releases taps after an app quits while the panel is closed.
    func reconcile(with apps: [AudioApp]) -> [String] {
        guard isControllingAnything else { return [] }

        let current = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })
        let available = Set(Self.outputDevices().map(\.uid))
        let systemDefault = Self.systemDefaultOutputUID()
        var failures: [String] = []

        for bundleID in Set(controlled.keys)
            .union(requestedGains.keys)
            .union(requestedRoutes.keys) {
            guard let app = current[bundleID] else {
                // An app leaves the Core Audio process list whenever it stops
                // playing, so a missing entry is not a reason to forget what
                // its owner chose. Only a quit app gets that.
                release(bundleID)
                if !Self.isRunning(bundleID) { forgetRequest(bundleID) }
                continue
            }

            let gain = requestedGains[bundleID] ?? 1
            let selected = requestedRoutes[bundleID]
            let effective = AudioRouting.effectiveDeviceUID(selected: selected,
                                                            available: available,
                                                            systemDefault: systemDefault)

            guard AudioRouting.needsTap(gain: gain, selected: selected,
                                        effective: effective, systemDefault: systemDefault) else {
                release(bundleID)
                continue
            }
            guard let effective else {
                // The Mac has no usable output at all. Say so once rather than
                // every poll for as long as that lasts.
                release(bundleID)
                forgetRequest(bundleID)
                failures.append("\(app.name): \(AppAudioError.noOutputDevice.localizedDescription)")
                continue
            }

            if let existing = controlled[bundleID] {
                guard existing.processObjectIDs != app.processObjectIDs
                        || existing.deviceUID != effective else {
                    if let failure = releaseIfRendererStalled(bundleID, playing: app.isPlaying) {
                        failures.append("\(app.name): \(failure)")
                    }
                    continue
                }
                release(bundleID)
            }

            do {
                controlled[bundleID] = try install(app, gain: gain, deviceUID: effective)
            } catch let error as AppAudioError {
                forgetRequest(bundleID)
                failures.append("\(app.name): \(error.localizedDescription)")
            } catch {
                forgetRequest(bundleID)
                failures.append("\(app.name): \(AppAudioError.setupFailed.localizedDescription)")
            }
        }
        return failures
    }

    // MARK: - Saved routes

    static let routesDefaultsKey = "audio.outputRoutes"

    /// Anything stored under this key was written by an older version or by
    /// hand, so a value that is not a device UID string is dropped rather than
    /// crashing the app on launch.
    static func savedRoutes(in defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: routesDefaultsKey)?
            .compactMapValues { $0 as? String } ?? [:]
    }

    static func persistRoutes(_ routes: [String: String], in defaults: UserDefaults = .standard) {
        guard !routes.isEmpty else {
            return defaults.removeObject(forKey: routesDefaultsKey)
        }
        defaults.set(routes, forKey: routesDefaultsKey)
    }

    /// A started device calls its IOProc continuously, so no callbacks at all
    /// while the app is producing output means the renderer is gone and the
    /// tap is muting the app into silence. Hand it back to the system mixer.
    private func releaseIfRendererStalled(_ bundleID: String, playing: Bool) -> String? {
        guard let control = controlled[bundleID] else { return nil }

        let ticks = control.renderTicks.load()
        guard playing, ticks == control.ticksAtLastPoll else {
            controlled[bundleID]?.ticksAtLastPoll = ticks
            controlled[bundleID]?.stalledPolls = 0
            return nil
        }

        let stalled = control.stalledPolls + 1
        guard stalled >= Self.stalledPollsBeforeRelease else {
            controlled[bundleID]?.stalledPolls = stalled
            return nil
        }
        release(bundleID)
        requestedGains.removeValue(forKey: bundleID)
        return "per-app volume stopped responding, so it is back at normal volume."
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated }
    }

    func releaseAll() {
        for bundleID in Array(controlled.keys) {
            release(bundleID)
        }
        requestedGains.removeAll()
        requestedRoutes.removeAll()
        Self.persistRoutes(requestedRoutes)
    }

    /// True while anything still needs maintaining: a live tap, a volume chosen
    /// for an app that has gone quiet, or a device chosen for one. A route is
    /// kept even when it matches the current default, because the app has to be
    /// moved back if that default changes.
    var isControllingAnything: Bool {
        !controlled.isEmpty || !requestedGains.isEmpty || !requestedRoutes.isEmpty
    }

    // MARK: - Tap and aggregate device

    private func install(_ app: AudioApp, gain: Float, deviceUID: String) throws -> Controlled {
        guard !app.processObjectIDs.isEmpty else { throw AppAudioError.setupFailed }

        // A mixdown tap is not tied to a device, which is what lets the
        // aggregate below play the app somewhere other than where it was
        // already going. It always hands over interleaved stereo, so the
        // destination's channel layout is the renderer's problem rather than a
        // reason to refuse the device.
        let description = CATapDescription(stereoMixdownOfProcesses: app.processObjectIDs)
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
              tapFormat.isInterleavedFloat else {
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw AppAudioError.unsupportedOutputDevice
        }

        let aggregate: Aggregate
        do {
            aggregate = try Self.createAggregate(
                named: "Switchboard \(app.name)",
                outputUID: deviceUID,
                tapUID: tapUID
            )
        } catch {
            _ = AudioHardwareDestroyProcessTap(tapID)
            throw error
        }

        let gainState = AtomicGain(gain)
        let renderTicks = RenderTicks()
        // Read once here rather than per callback: the audio thread must not
        // call into the HAL, and a tap's format does not change under it.
        let tapChannels = Int(tapFormat.channelsPerFrame)
        var ioProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregate.id,
            nil
        ) { _, input, _, output, _ in
            renderTicks.advance()
            let inputBuffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: input)
            )
            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
            guard let tapIndex = AudioRender.tapBufferIndex(in: inputBuffers,
                                                            tapChannels: tapChannels) else {
                // Core Audio hands the output buffer over holding whatever it
                // last contained, so a cycle with nothing to play still has to
                // write silence over it.
                AudioRender.silence(outputBuffers)
                return
            }
            AudioRender.render(source: inputBuffers[tapIndex],
                               into: outputBuffers,
                               gain: gainState.load())
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
            deviceUID: deviceUID,
            gain: gainState,
            tapID: tapID,
            aggregate: aggregate,
            ioProcID: ioProcID,
            renderTicks: renderTicks
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

        let timer = Timer(timeInterval: Self.teardownPollInterval, repeats: true) { [weak self] _ in
            self?.pollTeardowns()
        }
        RunLoop.main.add(timer, forMode: .common)
        teardownTimer = timer
    }

    private func pollTeardowns() {
        pendingTeardowns = pendingTeardowns.compactMap { pending in
            var pending = pending
            pending.polls += 1
            // Giving up leaks one tap and one aggregate for the rest of the
            // session, which is the lesser cost: the app has already been
            // handed back to the normal mixer, so nothing is left muted.
            guard pending.polls < Self.teardownPollLimit else {
                _ = AudioHardwareDestroyProcessTap(pending.tapID)
                return nil
            }

            if Self.string(pending.aggregate.id, kAudioDevicePropertyDeviceUID) == pending.aggregate.uid {
                _ = AudioHardwareDestroyAggregateDevice(pending.aggregate.id)
                return pending
            }

            let status = AudioHardwareDestroyProcessTap(pending.tapID)
            let stillThere = status != noErr && Self.objectExists(pending.tapID)
            return stillThere ? pending : nil
        }

        if pendingTeardowns.isEmpty {
            teardownTimer?.invalidate()
            teardownTimer = nil
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
            ]],
            // Without this the tap can stay idle after the device starts, which
            // leaves the app muted by the tap and rendered by nobody.
            kAudioAggregateDeviceTapAutoStartKey: true
        ]

        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID) == noErr,
              deviceID != kAudioObjectUnknown else {
            throw AppAudioError.setupFailed
        }
        return Aggregate(id: deviceID, uid: uid)
    }

    // MARK: - Core Audio property helpers

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
        // The fetch reports how many bytes it actually filled, which is fewer
        // than the size query above when the list shrinks between the two
        // calls. The untouched tail is still kAudioObjectUnknown, and passing
        // that on reads as a stream or process that does not exist.
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
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

    /// Teardown normally waits for Core Audio to finish destroying the
    /// aggregate asynchronously. At deinit there is no later poll, and the
    /// timer callback cannot reference an object that is already going away,
    /// so stop every renderer and destroy both objects directly.
    private func releaseEverythingSynchronously() {
        for bundleID in Array(controlled.keys) {
            guard let control = controlled.removeValue(forKey: bundleID) else { continue }
            control.gain.store(1)
            _ = AudioDeviceStop(control.aggregate.id, control.ioProcID)
            _ = AudioDeviceDestroyIOProcID(control.aggregate.id, control.ioProcID)
            pendingTeardowns.append(PendingTeardown(aggregate: control.aggregate,
                                                    tapID: control.tapID))
        }
        requestedGains.removeAll()

        for pending in pendingTeardowns {
            _ = AudioHardwareDestroyAggregateDevice(pending.aggregate.id)
            _ = AudioHardwareDestroyProcessTap(pending.tapID)
        }
        pendingTeardowns.removeAll()
    }

    deinit {
        teardownTimer?.invalidate()
        teardownTimer = nil
        releaseEverythingSynchronously()
    }
}
