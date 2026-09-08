import XCTest

/// The keep-awake row used to state only what the setting does, so a running
/// span gave no way to tell how much of it was left.
final class AwakeStatusTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func openEnded(after seconds: TimeInterval) -> String? {
        AwakeStatus.text(for: AwakeSpan(startedAt: start, endsAt: nil),
                         now: start.addingTimeInterval(seconds))
    }

    private func timed(minutes: Double, after seconds: TimeInterval) -> String? {
        AwakeStatus.text(for: AwakeSpan(startedAt: start,
                                        endsAt: start.addingTimeInterval(minutes * 60)),
                         now: start.addingTimeInterval(seconds))
    }

    func testOpenEndedStartsBelowAMinute() {
        XCTAssertEqual(openEnded(after: 0), "On for less than a minute")
        XCTAssertEqual(openEnded(after: 59), "On for less than a minute")
    }

    func testOpenEndedRoundsDownToWholeMinutes() {
        XCTAssertEqual(openEnded(after: 60), "On for 1 minute")
        XCTAssertEqual(openEnded(after: 119), "On for 1 minute")
        XCTAssertEqual(openEnded(after: 120), "On for 2 minutes")
    }

    func testOpenEndedSplitsHoursAndMinutes() {
        XCTAssertEqual(openEnded(after: 3600), "On for 1 hour")
        XCTAssertEqual(openEnded(after: 3660), "On for 1 hour 1 minute")
        XCTAssertEqual(openEnded(after: 5400), "On for 1 hour 30 minutes")
        XCTAssertEqual(openEnded(after: 7200), "On for 2 hours")
    }

    /// A clock that jumps backwards must not produce "On for -3 minutes".
    func testOpenEndedSurvivesAStartInTheFuture() {
        XCTAssertEqual(openEnded(after: -600), "On for less than a minute")
    }

    func testTimedSpanShowsItsFullLengthImmediately() {
        XCTAssertEqual(timed(minutes: 30, after: 0), "Ends in 30 minutes")
        XCTAssertEqual(timed(minutes: 60, after: 0), "Ends in 1 hour")
        XCTAssertEqual(timed(minutes: 120, after: 0), "Ends in 2 hours")
    }

    /// Rounding up keeps a 30 minute pick from reading as 29 a second later.
    func testTimedSpanRoundsRemainingUp() {
        XCTAssertEqual(timed(minutes: 30, after: 1), "Ends in 30 minutes")
        XCTAssertEqual(timed(minutes: 30, after: 60), "Ends in 29 minutes")
        XCTAssertEqual(timed(minutes: 120, after: 60), "Ends in 1 hour 59 minutes")
    }

    /// Rounding up means the final minute counts "1 minute" the whole way down
    /// and then disappears, rather than ever reading zero.
    func testTimedSpanHoldsAtOneMinuteUntilItExpires() {
        XCTAssertEqual(timed(minutes: 30, after: 1740), "Ends in 1 minute")
        XCTAssertEqual(timed(minutes: 30, after: 1799), "Ends in 1 minute")
        XCTAssertEqual(timed(minutes: 30, after: 1799.9), "Ends in 1 minute")
    }

    /// The row briefly read "Ends in 31 minutes" after a 30 minute pick, because
    /// the view passed a cached timeline date instead of the clock. Rounding up
    /// turns any lag at all, even a fraction of a second, into a whole extra
    /// minute, so the caller must always pass a live date.
    func testLaggingClockInflatesTheCountByAWholeMinute() {
        XCTAssertEqual(timed(minutes: 30, after: -0.1), "Ends in 31 minutes")
        XCTAssertEqual(timed(minutes: 30, after: -5), "Ends in 31 minutes")
        XCTAssertEqual(timed(minutes: 30, after: 0), "Ends in 30 minutes")
    }

    func testExpiredSpanReportsNothing() {
        XCTAssertNil(timed(minutes: 30, after: 1800))
        XCTAssertNil(timed(minutes: 30, after: 3600))
    }
}
