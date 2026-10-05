import XCTest

/// `split` drops empty subsequences, so these all used to under-report.
final class LineCountTests: XCTestCase {
    func testBlankLinesAreCounted() {
        XCTAssertEqual("one\n\n\ntwo".lineCount, 4)
    }

    func testOneTrailingNewlineEndsTheLastLine() {
        XCTAssertEqual("a\nb\n".lineCount, 2)
    }

    func testTwoTrailingNewlinesLeaveABlankLine() {
        XCTAssertEqual("a\nb\n\n".lineCount, 3)
    }

    func testSingleLine() {
        XCTAssertEqual("just one".lineCount, 1)
    }

    func testEmptyStringHasNoLines() {
        XCTAssertEqual("".lineCount, 0)
    }

    func testLoneNewlineIsOneEmptyLine() {
        XCTAssertEqual("\n".lineCount, 1)
    }

    /// The clip that produced "Show all 1 lines": long enough to offer
    /// expansion, but only one line to expand.
    func testLongSingleLineClipStillReportsOneLine() {
        let clip = ClipEntry(text: String(repeating: "a", count: 200),
                             imageData: nil, pixelSize: nil, date: Date(), note: nil)

        XCTAssertEqual(clip.lineCount, 1)
        XCTAssertGreaterThan(clip.preview.count, 90)
    }

    func testPreviewFlattensNewlinesAndTrims() {
        let clip = ClipEntry(text: "  first\nsecond  ", imageData: nil,
                             pixelSize: nil, date: Date(), note: nil)

        XCTAssertEqual(clip.preview, "first second")
    }

    /// The row only shows two lines, and flattening megabytes to draw them
    /// stalled the panel.
    func testPreviewOfALongClipKeepsOnlyItsStart() {
        let text = "\n\n  heading\n" + String(repeating: "body text\n", count: 100_000)
        let clip = ClipEntry(text: text, imageData: nil, pixelSize: nil, date: Date(), note: nil)

        XCTAssertTrue(clip.preview.hasPrefix("heading body text body text"))
        XCTAssertLessThanOrEqual(clip.preview.count, ClipEntry.previewCharacterLimit)
        XCTAssertFalse(clip.preview.contains("\n"))
        XCTAssertEqual(clip.lineCount, 100_003)
    }

    func testWhitespaceOnlyClipHasAnEmptyPreview() {
        let clip = ClipEntry(text: " \n\t\r\n ", imageData: nil, pixelSize: nil, date: Date(), note: nil)

        XCTAssertEqual(clip.preview, "")
    }

    func testExpandedTextIsTheWholeClipUpToTheLimit() {
        let atLimit = String(repeating: "a", count: ClipEntry.expandedCharacterLimit)
        let short = ClipEntry(text: atLimit, imageData: nil, pixelSize: nil, date: Date(), note: nil)
        XCTAssertFalse(short.exceedsExpandedLimit)
        XCTAssertEqual(short.expandedText, atLimit)

        let long = ClipEntry(text: atLimit + "b", imageData: nil, pixelSize: nil, date: Date(), note: nil)
        XCTAssertTrue(long.exceedsExpandedLimit)
        XCTAssertEqual(long.expandedText, atLimit, "the row lays out no more than the limit")
        XCTAssertEqual(long.text.count, ClipEntry.expandedCharacterLimit + 1, "Copy still has all of it")
    }

    func testImageClipHasNoTextToPreviewOrExpand() {
        let clip = ClipEntry(text: "", imageData: Data([1]), pixelSize: nil, date: Date(), note: nil)

        XCTAssertEqual(clip.preview, "")
        XCTAssertEqual(clip.lineCount, 0)
        XCTAssertFalse(clip.exceedsExpandedLimit)
    }
}

/// Text copied out of a Windows or classic-Mac app carries `\r\n` or a bare
/// `\r`. Counting those as line breaks in their own right double-counts every
/// line, and flattening only `\n` leaves the carriage return in the preview.
final class CarriageReturnTests: XCTestCase {
    func testWindowsLineEndingsCountOncePerLine() {
        XCTAssertEqual("one\r\ntwo\r\nthree".lineCount, 3)
    }

    func testWindowsTrailingLineEndingEndsTheLastLine() {
        XCTAssertEqual("a\r\nb\r\n".lineCount, 2)
    }

    func testClassicMacLineEndingsAreCounted() {
        XCTAssertEqual("one\rtwo".lineCount, 2)
    }

    func testMixedLineEndingsEachCountOnce() {
        XCTAssertEqual("a\r\rb\r\n\nc".lineCount, 5)
        XCTAssertEqual("\r\n".lineCount, 1)
        XCTAssertEqual("\n\r".lineCount, 2)
    }

    func testPreviewLeavesNoCarriageReturnBehind() {
        let clip = ClipEntry(text: "first\r\nsecond", imageData: nil,
                             pixelSize: nil, date: Date(), note: nil)

        XCTAssertEqual(clip.preview, "first second")
        XCTAssertFalse(clip.preview.contains("\r"))
    }
}
