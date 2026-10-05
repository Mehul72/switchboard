import XCTest

/// The ledger is what puts someone's own macOS settings back, so a mistake
/// here loses a value they chose. Every test writes a throwaway domain.
final class UndoLedgerTests: XCTestCase {
    private var domain = ""
    private var defaults: UserDefaults!
    private var ledger: UndoLedger!

    override func setUp() {
        super.setUp()
        domain = ScratchPreferenceDomain.make("ledger")
        defaults = InMemoryDefaults()
        ledger = UndoLedger(defaults: defaults)
    }

    override func tearDown() {
        for key in ["chosen", "absent", "other"] {
            PreferenceStore.write(nil, domain: domain, key: key)
        }
        ledger = nil
        defaults = nil
        super.tearDown()
    }

    private func stored(_ key: String) -> Any? {
        PreferenceStore.storedValue(domain: domain, key: key)
    }

    func testRestorePutsBackTheValueThatWasThere() {
        PreferenceStore.write(.string("mine"), domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "chosen")
        PreferenceStore.write(.string("switchboard"), domain: domain, key: "chosen")

        XCTAssertTrue(ledger.restoreAll())

        XCTAssertEqual(stored("chosen") as? String, "mine")
        XCTAssertTrue(ledger.isEmpty)
    }

    func testRestoreRemovesAKeyThatDidNotExist() {
        ledger.capture(domain: domain, key: "absent")
        PreferenceStore.write(.bool(true), domain: domain, key: "absent")

        XCTAssertTrue(ledger.restoreAll())

        XCTAssertNil(stored("absent"))
    }

    /// The second write is Switchboard's own value, not the owner's.
    func testOnlyTheFirstCaptureIsKept() {
        PreferenceStore.write(.int(1), domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "chosen")
        PreferenceStore.write(.int(2), domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "chosen")
        PreferenceStore.write(.int(3), domain: domain, key: "chosen")

        ledger.restoreAll()

        XCTAssertEqual((stored("chosen") as? NSNumber)?.intValue, 1)
    }

    func testRecordsSurviveARelaunch() {
        PreferenceStore.write(.string("mine"), domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "chosen")
        PreferenceStore.write(.string("switchboard"), domain: domain, key: "chosen")

        let relaunched = UndoLedger(defaults: defaults)
        XCTAssertFalse(relaunched.isEmpty)
        XCTAssertTrue(relaunched.restoreAll())

        XCTAssertEqual(stored("chosen") as? String, "mine")
        XCTAssertTrue(UndoLedger(defaults: defaults).isEmpty)
    }

    func testRestoringOneKeyLeavesTheOthersRecorded() {
        PreferenceStore.write(.string("mine"), domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "other")
        PreferenceStore.write(.string("switchboard"), domain: domain, key: "chosen")
        PreferenceStore.write(.string("switchboard"), domain: domain, key: "other")

        XCTAssertTrue(ledger.restore(domain: domain, key: "chosen"))

        XCTAssertEqual(stored("chosen") as? String, "mine")
        XCTAssertEqual(stored("other") as? String, "switchboard")
        XCTAssertFalse(ledger.isEmpty)
    }

    func testRestoringAKeyThatWasNeverCapturedChangesNothing() {
        PreferenceStore.write(.string("mine"), domain: domain, key: "chosen")

        XCTAssertTrue(ledger.restore(domain: domain, key: "chosen"))

        XCTAssertEqual(stored("chosen") as? String, "mine")
    }

    func testEmptyLedgerRestoresNothingAndReportsSuccess() {
        XCTAssertTrue(ledger.isEmpty)
        XCTAssertTrue(ledger.restoreAll())
    }

    /// A record with no domain or key cannot be restored. Keeping it would
    /// leave Restore Original Settings enabled for good.
    func testUnreadableRecordIsDropped() {
        defaults.set(["broken": ["value": 1]], forKey: "OriginalValues")
        let damaged = UndoLedger(defaults: defaults)
        XCTAssertFalse(damaged.isEmpty)

        XCTAssertTrue(damaged.restoreAll())

        XCTAssertTrue(damaged.isEmpty)
        XCTAssertNil(defaults.object(forKey: "OriginalValues"))
    }

    func testAffectedTargetsComeFromTheCatalogThenTheDomain() {
        let restartsFinder = Tweak(id: "test.flag", title: "Flag", category: .files, symbol: "eye",
                                   domain: domain, key: "chosen", onValue: .bool(true), restart: .finder)
        let needsNoRestart = Tweak(id: "test.plain", title: "Plain", category: .files, symbol: "eye",
                                   domain: domain, key: "other", onValue: .bool(true))
        ledger.capture(domain: domain, key: "chosen")
        ledger.capture(domain: domain, key: "other")
        XCTAssertEqual(ledger.affectedTargets(in: [restartsFinder, needsNoRestart]), [.finder])

        // A key from a retired tweak is no longer in the catalog; its domain still says who to restart.
        let orphaned = InMemoryDefaults()
        orphaned.set(["com.apple.dock/gone": ["domain": "com.apple.dock", "key": "gone"]], forKey: "OriginalValues")
        XCTAssertEqual(UndoLedger(defaults: orphaned).affectedTargets(in: []), [.dock])
    }
}
