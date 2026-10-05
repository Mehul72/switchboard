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

    /// `defaults write com.apple.finder AppleShowAllFiles YES` stores text,
    /// and Finder still shows hidden files. The toggle has to agree with it.
    func testBoolReadsStoredTextTheWayMacOSDoes() {
        for text in ["YES", "yes", "true", "TRUE", "1"] {
            XCTAssertTrue(PrefValue.bool(true).matches(text), text)
            XCTAssertFalse(PrefValue.bool(false).matches(text), text)
        }
        for text in ["NO", "no", "false", "0", ""] {
            XCTAssertTrue(PrefValue.bool(false).matches(text), text)
            XCTAssertFalse(PrefValue.bool(true).matches(text), text)
        }
    }

    func testBoolDoesNotMatchOtherStoredTypes() {
        XCTAssertFalse(PrefValue.bool(true).matches(Data([1])))
        XCTAssertFalse(PrefValue.bool(false).matches(["NO"]))
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

    func testScrollBarsStayVisibleForThisProcessOnly() {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        defaults.setVolatileDomain(original.merging(["SwitchboardTestArgument": "kept"]) { $1 },
                                   forName: UserDefaults.argumentDomain)
        let userSetting = PreferenceStore.effectiveValue(domain: "NSGlobalDomain", key: "AppleShowScrollBars") as? String

        PreferenceStore.keepScrollBarsVisible(in: defaults)

        XCTAssertEqual(defaults.string(forKey: "AppleShowScrollBars"), "Always")
        XCTAssertEqual(defaults.string(forKey: "SwitchboardTestArgument"), "kept")
        // The Show scroll bars tweak still reads the user's own setting.
        XCTAssertEqual(PreferenceStore.effectiveValue(domain: "NSGlobalDomain", key: "AppleShowScrollBars") as? String,
                       userSetting)
    }
}
