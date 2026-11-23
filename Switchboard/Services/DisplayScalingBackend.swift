import AppKit
import CoreGraphics
import OSLog

@MainActor
final class DisplayScalingBackend: DisplayScalingBackendProtocol {
    private final class Session {
        let display: ScalingDisplay
        let preset: DisplayScalePreset
        let originalMode: CGDisplayMode
        let origins: [CGDirectDisplayID: CGPoint]
        var source: SBVirtualDisplay?

        init(display: ScalingDisplay, preset: DisplayScalePreset, originalMode: CGDisplayMode,
             origins: [CGDirectDisplayID: CGPoint]) {
            self.display = display
            self.preset = preset
            self.originalMode = originalMode
            self.origins = origins
        }
    }

    private var session: Session?
    private let logger = Logger(subsystem: "com.Mehul72.switchboard", category: "display-scaling-backend")

    func displays() throws -> [ScalingDisplay] {
        let sourceID = session?.source?.displayID
        return try onlineIDs().filter { $0 != sourceID }.map { id in
            if let active = session, active.display.id == id { return active.display }
            return describe(id)
        }.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return !$0.isBuiltIn }
            return $0.id < $1.id
        }
    }

    func start(displayID: UInt32, preset: DisplayScalePreset) async throws {
        if let active = session {
            if active.display.id == displayID, active.preset == preset, isSessionValid() { return }
            throw failure("Restore the current display session before starting another preview.")
        }
        try Task.checkCancellation()
        guard preset.isValid else { throw failure("This desktop size is outside the supported range.") }
        guard try onlineIDs().contains(displayID) else { throw failure("The selected display is no longer connected.") }
        let display = describe(displayID)
        if let reason = display.unavailableReason { throw failure(reason) }
        guard !display.isBuiltIn, CGDisplayIsAsleep(displayID) == 0,
              preset.width <= display.nativeWidth, preset.height <= display.nativeHeight,
              abs(Double(preset.width) / Double(preset.height)
                  - Double(display.nativeWidth) / Double(display.nativeHeight)) < 0.01 else {
            throw failure("Choose a supported size for an awake external display.")
        }
        guard let originalMode = CGDisplayCopyDisplayMode(displayID),
              let native = nativeMode(for: display, preferredRate: originalMode.refreshRate) else {
            throw failure("macOS did not provide the display's native output mode. No settings were changed.")
        }
        let origins = try Dictionary(uniqueKeysWithValues: onlineIDs().compactMap { id -> (UInt32, CGPoint)? in
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { return nil }
            return (id, CGDisplayBounds(id).origin)
        })
        let active = Session(display: display, preset: preset, originalMode: originalMode, origins: origins)
        session = active
        do {
            let rate = native.refreshRate > 0 ? native.refreshRate : 60
            active.source = try SBVirtualDisplay(name: "Switchboard HiDPI", width: UInt32(preset.width),
                                                height: UInt32(preset.height), refreshRate: rate)
            guard let source = active.source else { throw failure("macOS could not create the HiDPI desktop.") }
            let wantedMode = try await waitForMode(on: source.displayID, session: active)
            try checkCurrent(active)

            // The physical output starts at its native mode, before joining the mirror set.
            try configure { config in
                try self.check(CGConfigureDisplayWithDisplayMode(config, displayID, native, nil),
                               action: "set the monitor's native output")
            }
            try checkCurrent(active)
            try configure { config in
                try self.check(CGConfigureDisplayWithDisplayMode(config, source.displayID, wantedMode, nil),
                               action: "select the HiDPI desktop size")
            }
            try await waitUntil(session: active) { self.matches(preset, mode: CGDisplayCopyDisplayMode(source.displayID)) }
            try configure { config in
                try self.check(CGConfigureDisplayMirrorOfDisplay(config, displayID, source.displayID),
                               action: "connect the monitor to the HiDPI desktop")
                if let origin = active.origins[displayID] {
                    try self.check(CGConfigureDisplayOrigin(config, source.displayID, Int32(origin.x), Int32(origin.y)),
                                   action: "preserve the display arrangement")
                }
            }
            try await waitUntil(session: active) { self.isSessionValid() }
            logger.info("Verified HiDPI desktop \(preset.width)x\(preset.height) on display \(displayID)")
        } catch {
            guard session === active else { throw error }
            do { try stop() }
            catch let restorationError {
                throw failure("\(error.localizedDescription) Restoration also failed: \(restorationError.localizedDescription)")
            }
            throw error
        }
    }

    func stop() throws {
        guard let active = session else { return }
        let physicalID = active.display.id
        let sourceID = active.source?.displayID
        let connected = Set(try onlineIDs())
        if connected.contains(physicalID), CGDisplayIsAsleep(physicalID) != 0 {
            active.source?.invalidate()
            active.source = nil
            throw failure("The monitor is asleep. Restore Original after it wakes, or quit Switchboard to reset the temporary configuration.")
        }
        if let sourceID, connected.contains(physicalID),
           CGDisplayMirrorsDisplay(physicalID) == sourceID {
            do {
                try configure { config in
                    try self.check(CGConfigureDisplayMirrorOfDisplay(config, physicalID, kCGNullDirectDisplay),
                                   action: "stop HiDPI mirroring")
                }
            } catch {
                // Removing the owned source is also a recovery path when Quartz rejects unmirroring.
                logger.error("Unmirror failed; removing owned source: \(error.localizedDescription, privacy: .public)")
            }
        }
        active.source?.invalidate()
        active.source = nil
        let remaining = Set(try onlineIDs())
        try configure { config in
            if remaining.contains(physicalID) {
                guard CGDisplayIsInMirrorSet(physicalID) == 0 else {
                    throw self.failure("The monitor is still mirrored. Try Restore Original again, or stop mirroring in macOS Displays settings.")
                }
                try self.check(CGConfigureDisplayWithDisplayMode(config, physicalID, active.originalMode, nil),
                               action: "restore the original monitor mode")
            }
            for (id, origin) in active.origins where remaining.contains(id) {
                guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay else { continue }
                try self.check(CGConfigureDisplayOrigin(config, id, Int32(origin.x), Int32(origin.y)),
                               action: "restore the display arrangement")
            }
        }
        session = nil
        logger.info("Restored display session for \(physicalID)")
    }

    func isSessionValid() -> Bool {
        guard let active = session, let source = active.source else { return false }
        let connected: Set<UInt32>
        do { connected = Set(try onlineIDs()) }
        catch {
            logger.error("Could not verify display connection: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard connected.contains(active.display.id), connected.contains(source.displayID),
              CGDisplayMirrorsDisplay(active.display.id) == source.displayID else { return false }
        // Hardware mirror sets may expose their shared mode only on the physical member.
        let mode = CGDisplayCopyDisplayMode(source.displayID) ?? CGDisplayCopyDisplayMode(active.display.id)
        return matches(active.preset, mode: mode)
    }

    private func describe(_ id: UInt32) -> ScalingDisplay {
        let info = SBDisplayInfo(id)
        let current = CGDisplayCopyDisplayMode(id)
        let width = (info?["kCGDisplayPixelWidth"] as? NSNumber)?.intValue ?? current?.pixelWidth ?? 0
        let height = (info?["kCGDisplayPixelHeight"] as? NSNumber)?.intValue ?? current?.pixelHeight ?? 0
        let builtIn = CGDisplayIsBuiltin(id) != 0
        let virtual = (info?["kCGDisplayIsVirtualDevice"] as? NSNumber)?.boolValue
        let airPlay = (info?["kCGDisplayIsAirPlay"] as? NSNumber)?.boolValue ?? false
        let reason: String?
        if builtIn { reason = "Use macOS Displays settings to scale the built-in screen." }
        else if !SBVirtualDisplay.isAvailable { reason = "HiDPI display support is unavailable on this version of macOS." }
        else if virtual == nil { reason = "macOS could not confirm that this is a directly connected physical monitor." }
        else if virtual == true || airPlay { reason = "Virtual, AirPlay, Sidecar, and DisplayLink displays are not supported." }
        else if CGDisplayIsInMirrorSet(id) != 0 { reason = "Stop existing mirroring in macOS Displays settings first." }
        else if CGDisplayRotation(id) != 0 { reason = "Return this display to standard rotation before using HiDPI scaling." }
        else if width < 800 || height < 600 { reason = "macOS did not provide a supported native display size." }
        else { reason = nil }
        return ScalingDisplay(id: id, name: displayName(id, info: info), nativeWidth: width,
                              nativeHeight: height, isBuiltIn: builtIn, unavailableReason: reason)
    }

    private func displayName(_ id: UInt32, info: [String: Any]?) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }) {
            return screen.localizedName
        }
        if let names = info?["DisplayProductName"] as? [String: String],
           let name = names[Locale.current.identifier] ?? names["en_US"] ?? names.sorted(by: { $0.key < $1.key }).first?.value {
            return name
        }
        return "Display \(id)"
    }

    private func nativeMode(for display: ScalingDisplay, preferredRate: Double) -> CGDisplayMode? {
        modes(on: display.id).filter {
            $0.width == display.nativeWidth && $0.height == display.nativeHeight
                && $0.pixelWidth == display.nativeWidth && $0.pixelHeight == display.nativeHeight
                && $0.isUsableForDesktopGUI()
        }.min { abs($0.refreshRate - preferredRate) < abs($1.refreshRate - preferredRate) }
    }

    private func modes(on id: UInt32) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
    }

    private func waitForMode(on id: UInt32, session active: Session) async throws -> CGDisplayMode {
        for _ in 0..<30 {
            try checkCurrent(active)
            if try onlineIDs().contains(id),
               let mode = modes(on: id).first(where: { matches(active.preset, mode: $0) }) { return mode }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw failure("macOS did not expose the requested HiDPI mode. Try a different desktop size.")
    }

    private func waitUntil(session active: Session, condition: () -> Bool) async throws {
        for _ in 0..<30 {
            try checkCurrent(active)
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw failure("macOS did not confirm the requested HiDPI configuration. Original settings will be restored.")
    }

    private func checkCurrent(_ active: Session) throws {
        try Task.checkCancellation()
        guard session === active else { throw CancellationError() }
        guard try onlineIDs().contains(active.display.id), CGDisplayIsAsleep(active.display.id) == 0 else {
            throw failure("The monitor disconnected or went to sleep during setup.")
        }
    }

    private func matches(_ preset: DisplayScalePreset, mode: CGDisplayMode?) -> Bool {
        guard let mode else { return false }
        return mode.width == preset.width && mode.height == preset.height
            && mode.pixelWidth == preset.width * 2 && mode.pixelHeight == preset.height * 2
    }

    private func onlineIDs() throws -> [UInt32] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count), action: "read connected displays")
        guard count > 0 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count), action: "read connected displays")
        return Array(ids.prefix(Int(count)))
    }

    private func configure(_ body: (CGDisplayConfigRef) throws -> Void) throws {
        var token: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&token), action: "begin display configuration")
        guard let token else { throw failure("macOS returned an invalid display configuration.") }
        do { try body(token) }
        catch {
            let cancelled = CGCancelDisplayConfiguration(token)
            if cancelled != .success { logger.error("Display transaction cancellation failed: \(cancelled.rawValue)") }
            throw error
        }
        try check(CGCompleteDisplayConfiguration(token, .forAppOnly), action: "apply temporary display configuration")
    }

    private func check(_ result: CGError, action: String) throws {
        guard result == .success else {
            throw failure("Could not \(action) (macOS error \(result.rawValue)).")
        }
    }

    private func failure(_ message: String) -> DisplayScalingError { .unavailable(message) }
}
