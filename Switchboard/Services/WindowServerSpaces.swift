import AppKit
import CoreGraphics

/// Window-server questions about Spaces, resolved at runtime so a macOS that
/// drops one of these private symbols degrades to "we cannot tell" instead of
/// failing to launch.
///
/// Accessibility cannot describe a window parked on a Space that is not
/// showing: the owning app's window list simply omits it. Measured on this
/// machine, Xcode and Spotify both reported zero Accessibility windows while
/// each had a real window sitting on another Space. The window server is the
/// only witness that those windows exist, and the only signal that separates a
/// real parked window from the leftover surfaces every app keeps around: real
/// windows belong to at least one Space, leftovers belong to none.
enum WindowServerSpaces {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Resolve = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Resolve.self)()
    }()

    private typealias CopySpacesForWindows =
        @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesForWindows? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesForWindows.self)
    }()

    private typealias CopyManagedDisplaySpaces =
        @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpaces? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyManagedDisplaySpaces.self)
    }()

    /// Whether the questions below can be answered at all in this session.
    /// Callers need this to tell "this surface belongs to no Space", which is
    /// the leftover signature, apart from "nobody can say", which must never
    /// be read as evidence that an app has run out of windows.
    static var canAnswer: Bool {
        connection != 0 && copySpacesForWindows != nil && copyManagedDisplaySpaces != nil
    }

    /// Every Space holding the window, ordinary desktops and full-screen
    /// Spaces alike. Empty for a leftover surface, and when unavailable.
    static func spaces(of window: CGWindowID) -> [UInt64] {
        guard connection != 0, let copySpacesForWindows else { return [] }
        // Desktop, full-screen and system Spaces together.
        let allSpaceKinds: Int32 = 0x7
        guard let listed = copySpacesForWindows(connection,
                                                allSpaceKinds,
                                                [NSNumber(value: window)] as CFArray)?
            .takeRetainedValue() as? [NSNumber] else { return [] }
        return listed.map(\.uint64Value)
    }

    /// The window server's number for a Space an app made by going full
    /// screen. A desktop is 0. Read on macOS 27 beside the Dock's own log of
    /// which Space was full screen.
    private static let fullScreenSpaceKind = 4

    /// What the server says about each display and its Spaces. Empty when unavailable.
    static func managedDisplays() -> [[String: Any]] {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]] else { return [] }
        return displays
    }

    /// The Space each display is showing right now. Empty when unavailable.
    static func visibleSpaces() -> Set<UInt64> {
        Set(managedDisplays().compactMap { display in
            ((display["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
        })
    }

    /// Whether the screen is showing an app's full-screen Space. False for a
    /// desktop, and when unavailable.
    static func isShowingFullScreenSpace(on screen: NSScreen?) -> Bool {
        showsFullScreenSpace(managedDisplays(), displayIdentifier: screen.flatMap(displayIdentifier(of:)))
    }

    /// The same question put to an answer already in hand, so it can be asked
    /// about displays this Mac does not have.
    static func showsFullScreenSpace(_ displays: [[String: Any]], displayIdentifier: String?) -> Bool {
        let named = displayIdentifier.flatMap { identifier in
            displays.first { $0["Display Identifier"] as? String == identifier }
        }
        // With one set of Spaces for every display the server answers once,
        // under a name that belongs to no display.
        let display = named ?? (displays.count == 1 ? displays.first : nil)
        let kind = ((display?["Current Space"] as? [String: Any])?["type"] as? NSNumber)?.intValue
        return kind == fullScreenSpaceKind
    }

    private static func displayIdentifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// A window the server places on at least one Space, none of them showing,
    /// is a real window parked elsewhere: one swipe away, so the app is still
    /// in use. A window on no Space at all is a leftover surface, the kind
    /// every app keeps around after its real windows are gone. A window on a
    /// Space that is showing needs no judgement here.
    static func isParkedOnHiddenSpace(windowSpaces: [UInt64],
                                      visibleSpaces: Set<UInt64>) -> Bool {
        guard !windowSpaces.isEmpty, !visibleSpaces.isEmpty else { return false }
        return !windowSpaces.contains { visibleSpaces.contains($0) }
    }
}
