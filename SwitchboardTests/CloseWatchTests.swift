import XCTest

/// The rule that decides whether a red-button click quits an app. Getting this
/// wrong terminates someone's editor, so each branch is pinned here.
final class CloseWatchTests: XCTestCase {
    private typealias Step = QuitOnCloseController.CloseWatchStep

    // MARK: - The reported bug

    /// VS Code was quit after a window swap that had nothing to do with the
    /// click: the app had already shown another window in between. Once the
    /// clicked window is gone and something else is open, the click is answered
    /// and the watch has to stop rather than keep sampling.
    func testWatchStopsOnceAnotherWindowIsOpen() {
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(after: .otherWindowsRemain, emptySamples: 0),
            .stop
        )
    }

    /// The same, after the app had already been seen with nothing open. A
    /// window appearing settles the question in the other direction.
    func testAWindowAppearingAfterAnEmptySampleStopsTheWatch() {
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(after: .otherWindowsRemain, emptySamples: 1),
            .stop
        )
    }

    // MARK: - The feature still working

    func testTheLastAgreeingSampleQuits() {
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(
                after: .appHasNoWindows,
                emptySamples: QuitOnCloseController.emptySamplesBeforeQuit - 1),
            .quit
        )
    }

    /// One short of the bar is still not a quit, whatever the bar is set to.
    func testOneSampleShortOfTheBarKeepsWatching() {
        let short = QuitOnCloseController.emptySamplesBeforeQuit - 2
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(after: .appHasNoWindows, emptySamples: short),
            .keepWatching(emptySamples: short + 1)
        )
    }

    /// Chrome blanks its window list for over a second mid full-screen, so the
    /// agreement window has to outlast that.
    func testTheBarOutlastsAFullScreenTransition() {
        let agreementSeconds = Double(QuitOnCloseController.emptySamplesBeforeQuit) * 0.25
        XCTAssertGreaterThan(agreementSeconds, 1.0,
                             "a full-screen transition blanks the list for over a second")
    }

    func testOneEmptySampleIsNotEnoughToQuit() {
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(after: .appHasNoWindows, emptySamples: 0),
            .keepWatching(emptySamples: 1)
        )
    }

    func testWindowStillClosingKeepsWaiting() {
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(after: .stillClosing, emptySamples: 0),
            .keepWatching(emptySamples: 0)
        )
    }

    // MARK: - Never quit on missing information

    func testAccessibilitySilenceResetsTheTally() {
        XCTAssertEqual(
            QuitOnCloseController.nextCloseWatchStep(after: .unknown, emptySamples: 1),
            .keepWatching(emptySamples: 0)
        )
    }

    /// A blank answer during a Space transition, sandwiched between real ones,
    /// must not accumulate toward a quit.
    func testFlickerBetweenEmptySamplesCannotReachAQuit() {
        var empty = 0
        for outcome in [QuitOnCloseController.CloseOutcome.appHasNoWindows,
                        .unknown,
                        .appHasNoWindows] {
            switch QuitOnCloseController.nextCloseWatchStep(after: outcome, emptySamples: empty) {
            case .keepWatching(let next): empty = next
            case .quit: return XCTFail("a single blank sample must not be enough to quit")
            case .stop: return XCTFail("nothing here settles the question")
            }
        }
        XCTAssertEqual(empty, 1)
    }

    /// The legitimate case end to end: click the red button on the only
    /// window, it goes away, nothing is left.
    func testClosingTheLastWindowStillQuits() {
        var empty = 0
        var quit = false
        let outcomes = [QuitOnCloseController.CloseOutcome.stillClosing]
            + Array(repeating: .appHasNoWindows, count: QuitOnCloseController.emptySamplesBeforeQuit)
        for outcome in outcomes {
            switch QuitOnCloseController.nextCloseWatchStep(after: outcome, emptySamples: empty) {
            case .keepWatching(let next): empty = next
            case .quit: quit = true
            case .stop: return XCTFail("nothing here settles the question early")
            }
        }
        XCTAssertTrue(quit, "closing the last window is what the feature exists to do")
    }

    /// Closing one window of several is an ordinary close and nothing more.
    func testClosingOneOfSeveralWindowsNeverQuits() {
        var empty = 0
        for outcome in [QuitOnCloseController.CloseOutcome.stillClosing, .otherWindowsRemain] {
            switch QuitOnCloseController.nextCloseWatchStep(after: outcome, emptySamples: empty) {
            case .keepWatching(let next): empty = next
            case .quit: return XCTFail("the app still has windows open")
            case .stop: return
            }
        }
        XCTFail("the watch should have stopped")
    }
}

/// Reading the two window sources. Accessibility is the authority; pixels on
/// screen only ever mean "not settled yet".
final class CloseOutcomeTests: XCTestCase {
    private func outcome(clicked: Bool, others: Bool, visible: Bool) -> QuitOnCloseController.CloseOutcome {
        QuitOnCloseController.closeOutcome(clickedWindowStillListed: clicked,
                                          hasOtherAccessibilityWindows: others,
                                          anythingVisible: visible)
    }

    /// The bug that made the feature quit nothing at all: Accessibility drops
    /// the window before its close animation finishes, so the first sample saw
    /// an empty window list with pixels still on screen. Calling that
    /// "otherWindowsRemain" was terminal and ended every watch immediately.
    func testAClosingAnimationIsNotAnotherWindow() {
        XCTAssertEqual(outcome(clicked: false, others: false, visible: true), .stillClosing,
                       "pixels mid-animation mean wait, not stop")
    }

    func testTheClickedWindowStillListedKeepsWaiting() {
        XCTAssertEqual(outcome(clicked: true, others: false, visible: true), .stillClosing)
        XCTAssertEqual(outcome(clicked: true, others: true, visible: true), .stillClosing)
    }

    /// Only Accessibility can settle the question against quitting.
    func testARealOtherWindowStopsTheWatch() {
        XCTAssertEqual(outcome(clicked: false, others: true, visible: true), .otherWindowsRemain)
        XCTAssertEqual(outcome(clicked: false, others: true, visible: false), .otherWindowsRemain)
    }

    func testNothingListedAndNothingVisibleIsAnEmptyApp() {
        XCTAssertEqual(outcome(clicked: false, others: false, visible: false), .appHasNoWindows)
    }

    /// End to end through both stages: the animation settles, then six
    /// agreeing samples quit the app.
    func testAnimationThenQuiet() {
        var empty = 0
        var quit = false
        let samples = [outcome(clicked: true, others: false, visible: true),
                       outcome(clicked: false, others: false, visible: true)]
            + Array(repeating: outcome(clicked: false, others: false, visible: false),
                    count: QuitOnCloseController.emptySamplesBeforeQuit)
        for sample in samples {
            switch QuitOnCloseController.nextCloseWatchStep(after: sample, emptySamples: empty) {
            case .keepWatching(let next): empty = next
            case .quit: quit = true
            case .stop: return XCTFail("a close animation must not settle the question")
            }
        }
        XCTAssertTrue(quit)
    }
}

/// Both Accessibility-gated features used to wipe the stored preference when
/// permission was missing at launch, so granting it afterwards brought nothing
/// back. The preference is what the user asked for; the hook follows the
/// permission.
final class AccessibilityResumeTests: XCTestCase {
    private func step(preference: Bool, permitted: Bool, running: Bool) -> AccessibilityResumeStep {
        AccessibilityResumeStep.next(preferenceOn: preference, permitted: permitted, running: running)
    }

    func testPermissionArrivingAfterLaunchStartsTheFeature() {
        XCTAssertEqual(step(preference: true, permitted: true, running: false), .start)
    }

    func testMissingPermissionLeavesAStoppedFeatureAlone() {
        XCTAssertEqual(step(preference: true, permitted: false, running: false), .leaveAlone,
                       "the preference has to survive so a later grant can resume it")
    }

    func testRevokedPermissionStopsARunningHook() {
        XCTAssertEqual(step(preference: true, permitted: true, running: true), .leaveAlone)
        XCTAssertEqual(step(preference: true, permitted: false, running: true), .stop)
    }

    func testPreferenceOffStopsARunningHook() {
        XCTAssertEqual(step(preference: false, permitted: true, running: true), .stop)
    }

    func testPreferenceOffNeverStartsAnything() {
        XCTAssertEqual(step(preference: false, permitted: true, running: false), .leaveAlone)
        XCTAssertEqual(step(preference: false, permitted: false, running: false), .leaveAlone)
    }

    func testAlreadyRunningAndWantedIsNotRestarted() {
        XCTAssertEqual(step(preference: true, permitted: true, running: true), .leaveAlone)
    }
}
