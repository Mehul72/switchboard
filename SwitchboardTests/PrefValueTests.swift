import XCTest

/// Preferences come back from CFPreferences as untyped plist values, so every
/// comparison goes through a coercion that has to be exact.
final class PrefValueTests: XCTestCase {
    func testMissingPreferenceNeverMatches() {
        XCTAssertFalse(PrefValue.bool(true).matches(nil))
        XCTAssertFalse(PrefValue.bool(false).matches(nil))
        XCTAssertFalse(PrefValue.int(0).matches(nil))
        XCTAssertFalse(PrefValue.float(0).matches(nil))
        XCTAssertFalse(PrefValue.string("").matches(nil))
    }

    func testBoolReadsStoredNumbers() {
        XCTAssertTrue(PrefValue.bool(true).matches(NSNumber(value: true)))
        XCTAssertTrue(PrefValue.bool(false).matches(NSNumber(value: 0)))
        XCTAssertFalse(PrefValue.bool(true).matches(NSNumber(value: false)))
    }

    func testBoolDoesNotMatchAString() {
        XCTAssertFalse(PrefValue.bool(true).matches("1"))
    }

    func testIntComparesExactly() {
        XCTAssertTrue(PrefValue.int(120).matches(NSNumber(value: 120)))
        XCTAssertFalse(PrefValue.int(120).matches(NSNumber(value: 121)))
    }

    /// autohide-delay is written as a double, and reading it back must not
    /// fail on floating point noise.
    func testFloatComparesWithinTolerance() {
        XCTAssertTrue(PrefValue.float(0).matches(NSNumber(value: 0.00001)))
        XCTAssertFalse(PrefValue.float(0).matches(NSNumber(value: 0.5)))
    }

    func testStringIsCaseSensitive() {
        XCTAssertTrue(PrefValue.string("Always").matches("Always"))
        XCTAssertFalse(PrefValue.string("Always").matches("always"))
    }

    func testStringDoesNotMatchANumber() {
        XCTAssertFalse(PrefValue.string("1").matches(NSNumber(value: 1)))
    }
}
