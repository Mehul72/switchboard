import XCTest

final class WelcomeGateTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "Switchboard.WelcomeGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WelcomeGateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
        defaults = nil
        try super.tearDownWithError()
    }

    func testFirstLaunchOfACopyClaimsTheWelcome() {
        XCTAssertTrue(WelcomeGate(defaults: defaults).claim(copy("100-30")))
    }

    func testRelaunchingTheSameCopyNeverShowsItAgain() {
        XCTAssertTrue(WelcomeGate(defaults: defaults).claim(copy("100-30")))
        XCTAssertFalse(WelcomeGate(defaults: defaults).claim(copy("100-30")))
        XCTAssertFalse(WelcomeGate(defaults: defaults).claim(copy("100-30")))
    }

    func testANewCopyShowsItEvenAfterAnotherCopyDid() {
        XCTAssertTrue(WelcomeGate(defaults: defaults).claim(copy("100-30")))
        XCTAssertTrue(WelcomeGate(defaults: defaults).claim(copy("200-30")))
    }

    func testSwitchingBetweenTwoCopiesDoesNotReshowEither() {
        let gate = WelcomeGate(defaults: defaults)
        XCTAssertTrue(gate.claim(copy("debug")))
        XCTAssertTrue(gate.claim(copy("installed")))
        XCTAssertFalse(gate.claim(copy("debug")))
        XCTAssertFalse(gate.claim(copy("installed")))
    }

    func testLimitDropsTheLeastRecentlyLaunchedCopy() {
        let gate = WelcomeGate(defaults: defaults)
        XCTAssertTrue(gate.claim(copy("installed")))
        for build in 1...WelcomeGate.rememberedCopyLimit {
            XCTAssertTrue(gate.claim(copy("debug-\(build)")))
            // The installed copy keeps launching, so it must never be the one dropped.
            XCTAssertFalse(gate.claim(copy("installed")))
        }
        let stored = defaults.stringArray(forKey: WelcomeGate.shownCopiesKey) ?? []
        XCTAssertEqual(stored.count, WelcomeGate.rememberedCopyLimit)
        XCTAssertEqual(stored.last, "installed")
        XCTAssertFalse(stored.contains("debug-1"))
        XCTAssertTrue(gate.claim(copy("debug-1")))
    }

    func testUnreadableStoredValueIsReplaced() {
        defaults.set(42, forKey: WelcomeGate.shownCopiesKey)
        let gate = WelcomeGate(defaults: defaults)
        XCTAssertTrue(gate.claim(copy("100-30")))
        XCTAssertEqual(defaults.stringArray(forKey: WelcomeGate.shownCopiesKey), ["100-30"])
        XCTAssertFalse(gate.claim(copy("100-30")))
    }

    func testCopyIDIsStableForTheSameBundle() throws {
        let bundle = try makeBundle(named: "Switchboard.app")
        XCTAssertEqual(try AppCopy(bundleURL: bundle, build: "30"),
                       try AppCopy(bundleURL: bundle, build: "30"))
    }

    func testMovingTheBundleKeepsItsCopyID() throws {
        let original = try makeBundle(named: "Switchboard.app")
        let before = try AppCopy(bundleURL: original, build: "30")
        let destination = folder.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let moved = destination.appendingPathComponent("Switchboard.app", isDirectory: true)
        try FileManager.default.moveItem(at: original, to: moved)
        XCTAssertEqual(try AppCopy(bundleURL: moved, build: "30"), before)
    }

    func testDeletingAndReinstallingGivesANewCopyID() throws {
        let bundle = try makeBundle(named: "Switchboard.app")
        let before = try AppCopy(bundleURL: bundle, build: "30")
        try FileManager.default.removeItem(at: bundle)
        let reinstalled = try makeBundle(named: "Switchboard.app")
        XCTAssertNotEqual(try AppCopy(bundleURL: reinstalled, build: "30"), before)
    }

    func testCopyingTheBundleGivesANewCopyID() throws {
        let bundle = try makeBundle(named: "Switchboard.app")
        let duplicate = folder.appendingPathComponent("Copy.app", isDirectory: true)
        try FileManager.default.copyItem(at: bundle, to: duplicate)
        XCTAssertNotEqual(try AppCopy(bundleURL: duplicate, build: "30"),
                          try AppCopy(bundleURL: bundle, build: "30"))
    }

    func testDifferentBuildsAtTheSameInodeAreDifferentCopies() throws {
        let bundle = try makeBundle(named: "Switchboard.app")
        XCTAssertNotEqual(try AppCopy(bundleURL: bundle, build: "30"),
                          try AppCopy(bundleURL: bundle, build: "31"))
    }

    func testMissingBundleThrows() {
        let missing = folder.appendingPathComponent("Missing.app", isDirectory: true)
        XCTAssertThrowsError(try AppCopy(bundleURL: missing, build: "30")) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOENT)
        }
    }

    private func copy(_ id: String) -> AppCopy {
        AppCopy(id: id)
    }

    private func makeBundle(named name: String) throws -> URL {
        let bundle = folder.appendingPathComponent(name, isDirectory: true)
        let executable = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executable, withIntermediateDirectories: true)
        return bundle
    }
}
