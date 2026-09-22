import XCTest

/// macOS copies the old "target" and "location" screencapture keys into
/// per-mode keys the first time it needs them, then reads only the per-mode
/// keys. Writing just the old key therefore works once and is ignored from
/// then on. Each test runs against a throwaway domain, never the real one.
final class CaptureDestinationTests: XCTestCase {
    private let screencaptureKeys = ["target", "target-screenshot",
                                     "location", "location-screenshot"]
    private var domain = ""

    override func setUp() {
        super.setUp()
        domain = "com.switchboard.tests.capture.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        PreferenceStore.write(nil, domain: domain, keys: screencaptureKeys)
        // cfprefsd keeps the emptied plist, which would pile up one per run.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(domain).plist")
        if FileManager.default.fileExists(atPath: plist.path) {
            try FileManager.default.removeItem(at: plist)
        }
        try super.tearDownWithError()
    }

    private func spec(_ id: String) throws -> PreferenceSpec {
        let tweak = try XCTUnwrap(TweakCatalog.capture.first { $0.id == id })
        return try XCTUnwrap(tweak.preference)
    }

    private func stored(_ key: String) -> String? {
        PreferenceStore.storedValue(domain: domain, key: key) as? String
    }

    /// The state a Mac is left in after one screenshot taken with clipboard
    /// capture on: both keys say clipboard.
    private func seedCopiedClipboardTarget() {
        PreferenceStore.write(.string("clipboard"), domain: domain, key: "target")
        PreferenceStore.write(.string("clipboard"), domain: domain, key: "target-screenshot")
    }

    func testTurningClipboardOffReachesTheKeyScreencaptureReads() throws {
        let clipboard = try spec("capture.clipboard")
        seedCopiedClipboardTarget()

        XCTAssertTrue(PreferenceStore.write(clipboard.offValue, domain: domain, keys: clipboard.keys))

        XCTAssertEqual(stored("target-screenshot"), "file")
        XCTAssertEqual(stored("target"), "file", "releases before the split still read this key")
    }

    func testClipboardToggleShowsWhatScreencaptureWillDo() throws {
        let clipboard = try spec("capture.clipboard")
        // Switchboard turned the old key off, but macOS still obeys the new one.
        PreferenceStore.write(.string("file"), domain: domain, key: "target")
        PreferenceStore.write(.string("clipboard"), domain: domain, key: "target-screenshot")

        let shown = PreferenceStore.effectiveValue(domain: domain, keys: clipboard.keys)

        XCTAssertTrue(clipboard.onValue.matches(shown))
    }

    func testClipboardToggleReadsTheOldKeyUntilMacOSCopiesIt() throws {
        let clipboard = try spec("capture.clipboard")
        PreferenceStore.write(.string("clipboard"), domain: domain, key: "target")

        let shown = PreferenceStore.effectiveValue(domain: domain, keys: clipboard.keys)

        XCTAssertTrue(clipboard.onValue.matches(shown))
    }

    func testChangingTheFolderReachesTheKeyScreencaptureReads() throws {
        let location = try spec("capture.location")
        PreferenceStore.write(.string("/Users/test/Desktop"), domain: domain, key: "location")
        PreferenceStore.write(.string("/Users/test/Desktop"), domain: domain, key: "location-screenshot")

        XCTAssertTrue(PreferenceStore.write(.string("/Users/test/Shots"), domain: domain, keys: location.keys))

        XCTAssertEqual(stored("location-screenshot"), "/Users/test/Shots")
        XCTAssertEqual(stored("location"), "/Users/test/Shots")
        XCTAssertEqual(PreferenceStore.effectiveValue(domain: domain, keys: location.keys) as? String,
                       "/Users/test/Shots")
    }

    func testClearingRemovesEveryKey() {
        seedCopiedClipboardTarget()

        XCTAssertTrue(PreferenceStore.write(nil, domain: domain, keys: ["target-screenshot", "target"]))

        XCTAssertNil(stored("target-screenshot"))
        XCTAssertNil(stored("target"))
    }
}
