import Foundation

/// Decides which output device an app's audio actually reaches, and whether
/// Switchboard has to tap the app at all to put it there.
///
/// Kept apart from the Core Audio plumbing because these are the rules that
/// decide when a person's audio gets intercepted, and they are worth pinning
/// down without a sound card in the loop.
enum AudioRouting {
    /// Aggregate devices Switchboard builds to render through. They are created
    /// private, but private means private to this process, not invisible to it,
    /// so they come back from the HAL's own device list and have to be filtered
    /// out before the list is offered to a person.
    static let ownDeviceUIDPrefix = "com.Mehul72.switchboard."

    static func isOwnDevice(uid: String) -> Bool {
        uid.hasPrefix(ownDeviceUIDPrefix)
    }

    /// Whether a Core Audio device belongs in the list a person picks from.
    ///
    /// An input-only device cannot play anything, a dead device is one that has
    /// been unplugged since the list was fetched, and Switchboard's own render
    /// aggregates would let someone route an app into the machinery moving it.
    static func isSelectableOutput(uid: String, isAlive: Bool, hasOutputStreams: Bool) -> Bool {
        isAlive && hasOutputStreams && !isOwnDevice(uid: uid)
    }

    /// Whether a gain is close enough to full volume to count as untouched.
    ///
    /// The slider is continuous, so dragging back to the top lands on values
    /// like 0.9998 that display as 100%. Treating those as attenuated keeps a
    /// tap, and its audio privacy indicator, alive for the rest of the session
    /// with nothing on screen to explain why.
    static func isFullVolume(_ gain: Float) -> Bool {
        gain >= 1 - displayedPercentTolerance
    }

    /// Half of the one percent step the row displays.
    private static let displayedPercentTolerance: Float = 0.005

    /// The device an app's audio ends up on: the one it was sent to while that
    /// device is still present, and the system default otherwise.
    ///
    /// Falling back rather than going silent is deliberate. Unplugging an
    /// interface should not mute an app until someone reopens Switchboard.
    static func effectiveDeviceUID(selected: String?,
                                   available: Set<String>,
                                   systemDefault: String?) -> String? {
        guard let selected, available.contains(selected) else { return systemDefault }
        return selected
    }

    /// True when a device was chosen for an app and has since gone away, so the
    /// row can say so instead of silently showing the default.
    static func selectedDeviceIsMissing(selected: String?, available: Set<String>) -> Bool {
        guard let selected else { return false }
        return !available.contains(selected)
    }

    /// Whether the app needs a tap.
    ///
    /// Full volume on the system default is the one case that needs nothing:
    /// the app is already doing exactly what the user asked for, so it is left
    /// on its own path untouched. Every other case has to intercept.
    static func needsTap(gain: Float,
                         selected: String?,
                         effective: String?,
                         systemDefault: String?) -> Bool {
        // Nowhere to render means a tap could only mute the app.
        guard effective != nil else { return false }
        if !isFullVolume(gain) { return true }
        guard let selected else { return false }
        // With no known default, a chosen device is the only instruction there
        // is, so honour it.
        guard let systemDefault else { return true }
        return selected != systemDefault && effective != systemDefault
    }
}
