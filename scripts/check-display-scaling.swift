import AppKit
import CoreGraphics
import Darwin

@main
enum DisplayScalingCheck {
    private struct OriginalDisplay {
        let id: UInt32
        let mode: CGDisplayMode
        let bounds: CGRect
        let mirror: UInt32
    }

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            fputs("Display scaling check exceeded 30 seconds. Temporary displays will be removed on exit.\n", stderr)
            exit(1)
        }
        Task { @MainActor in
            do {
                try await checkVirtualMirroring()
                exit(0)
            } catch {
                fputs("Display scaling check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        // A hostless XCTest run loop does not service virtual-display mode discovery.
        app.run()
    }

    @MainActor
    private static func checkVirtualMirroring() async throws {
        guard SBVirtualDisplay.isAvailable else { throw failure("Required display classes are unavailable.") }
        let originals = try onlineIDs().map { id -> OriginalDisplay in
            guard let mode = CGDisplayCopyDisplayMode(id) else { throw failure("An original display mode is unavailable.") }
            return OriginalDisplay(id: id, mode: mode, bounds: CGDisplayBounds(id), mirror: CGDisplayMirrorsDisplay(id))
        }
        guard !originals.isEmpty else { throw failure("This check requires a logged-in graphical desktop.") }
        let target = try SBVirtualDisplay(name: "Switchboard Test Target", width: 3440, height: 1440, refreshRate: 60)
        defer { target.invalidate() }
        let source = try SBVirtualDisplay(name: "Switchboard Test Source", width: 2752, height: 1152, refreshRate: 60)
        defer { source.invalidate() }
        let targetID = target.displayID
        let sourceID = source.displayID
        let native = try await waitForMode(display: targetID, width: 3440, height: 1440, scale: 1)
        let hiDPI = try await waitForMode(display: sourceID, width: 2752, height: 1152, scale: 2)
        guard let originalTargetMode = CGDisplayCopyDisplayMode(targetID) else {
            throw failure("The disposable target has no current mode.")
        }
        print("PASS: requested 2752 × 1152 desktop exposes a 5504 × 2304 backing mode")

        let backend = DisplayScalingBackend()
        let described = try backend.displays().first { $0.id == targetID }
        guard described?.unavailableReason?.contains("Virtual") == true else {
            throw failure("The backend did not reject a virtual display as a user-selected scaling target.")
        }
        print("PASS: virtual displays cannot be selected as physical scaling targets")

        try configure { config in
            try check(CGConfigureDisplayWithDisplayMode(config, targetID, native, nil), "set disposable target native mode")
        }
        try configure { config in
            try check(CGConfigureDisplayWithDisplayMode(config, sourceID, hiDPI, nil), "set source HiDPI mode")
        }
        let origin = CGDisplayBounds(targetID).origin
        try configure { config in
            try check(CGConfigureDisplayMirrorOfDisplay(config, targetID, sourceID), "mirror the disposable target")
            try check(CGConfigureDisplayOrigin(config, sourceID, Int32(origin.x), Int32(origin.y)), "place the virtual source")
        }
        try await waitUntil {
            let ids = try onlineIDs()
            let mode = CGDisplayCopyDisplayMode(sourceID) ?? CGDisplayCopyDisplayMode(targetID)
            return ids.contains(sourceID) && ids.contains(targetID)
                && CGDisplayMirrorsDisplay(targetID) == sourceID
                && matches(mode, width: 2752, height: 1152, scale: 2)
        }
        print("PASS: mirroring preserves the requested HiDPI source mode")

        try configure { config in
            try check(CGConfigureDisplayMirrorOfDisplay(config, targetID, kCGNullDirectDisplay), "unmirror the disposable target")
        }
        source.invalidate()
        try configure { config in
            try check(CGConfigureDisplayWithDisplayMode(config, targetID, originalTargetMode, nil), "restore the disposable target")
        }
        target.invalidate()
        try await waitUntil {
            let ids = try onlineIDs()
            return !ids.contains(sourceID) && !ids.contains(targetID)
        }
        print("PASS: both temporary displays are removed")

        let remaining = try onlineIDs()
        guard Set(remaining) == Set(originals.map(\.id)) else {
            throw failure("The connected display inventory changed during the check.")
        }
        for original in originals {
            guard let mode = CGDisplayCopyDisplayMode(original.id),
                  mode.width == original.mode.width, mode.height == original.mode.height,
                  mode.pixelWidth == original.mode.pixelWidth, mode.pixelHeight == original.mode.pixelHeight,
                  abs(mode.refreshRate - original.mode.refreshRate) < 0.01,
                  CGDisplayBounds(original.id) == original.bounds,
                  CGDisplayMirrorsDisplay(original.id) == original.mirror else {
                throw failure("An original display's mode or arrangement changed during the check.")
            }
        }
        print("PASS: all original display modes, refresh rates, arrangements and mirror relationships are unchanged")
    }

    @MainActor
    private static func waitForMode(display: UInt32, width: Int, height: Int, scale: Int) async throws -> CGDisplayMode {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        for _ in 0..<50 {
            if try onlineIDs().contains(display),
               let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode],
               let mode = modes.first(where: { matches($0, width: width, height: height, scale: scale) }) { return mode }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw failure("Missing mode \(width) × \(height) at \(scale)× backing scale.")
    }

    @MainActor
    private static func waitUntil(_ condition: () throws -> Bool) async throws {
        for _ in 0..<50 {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw failure("WindowServer did not reach the expected configuration before the deadline.")
    }

    private static func matches(_ mode: CGDisplayMode?, width: Int, height: Int, scale: Int) -> Bool {
        guard let mode else { return false }
        return mode.width == width && mode.height == height
            && mode.pixelWidth == width * scale && mode.pixelHeight == height * scale
    }

    private static func onlineIDs() throws -> [UInt32] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count), "count connected displays")
        guard count > 0 else { return [] }
        var ids = [UInt32](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count), "read connected displays")
        return Array(ids.prefix(Int(count)))
    }

    private static func configure(_ body: (CGDisplayConfigRef) throws -> Void) throws {
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), "begin configuration")
        guard let config else { throw failure("Missing configuration token.") }
        do { try body(config) }
        catch {
            try check(CGCancelDisplayConfiguration(config), "cancel configuration")
            throw error
        }
        try check(CGCompleteDisplayConfiguration(config, .forAppOnly), "complete temporary configuration")
    }

    private static func check(_ result: CGError, _ action: String) throws {
        guard result == .success else { throw failure("Could not \(action): \(result.rawValue).") }
    }

    private static func failure(_ description: String) -> NSError {
        NSError(domain: "Switchboard.DisplayScalingCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
}
