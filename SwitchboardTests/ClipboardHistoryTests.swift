import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// Recording rules for the clipboard history, driven against a private
/// pasteboard so the tests never touch the real one.
final class ClipboardHistoryTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var history: ClipboardHistory!

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("switchboard-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        history = ClipboardHistory(pasteboard: pasteboard)
    }

    override func tearDown() {
        history = nil
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Concealed clips

    func testConcealedMarkerOnTheFirstItemSuppressesTheClip() {
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setString("1", forType: Self.concealed)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        history.capture()

        XCTAssertTrue(history.entries.isEmpty)
    }

    func testConcealedMarkerOnALaterItemSuppressesTheClip() {
        let secret = NSPasteboardItem()
        secret.setString("hunter2", forType: .string)
        let marker = NSPasteboardItem()
        marker.setString("1", forType: Self.concealed)
        pasteboard.clearContents()
        pasteboard.writeObjects([secret, marker])

        history.capture()

        XCTAssertTrue(history.entries.isEmpty,
                      "a marker on any item has to suppress the whole write, not just the first")
    }

    func testOrdinaryTextIsRecorded() {
        copy("plain text")

        history.capture()

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.text, "plain text")
    }

    // MARK: - Recording rules

    func testWhitespaceOnlyClipIsIgnored() {
        copy("   \n  \t ")

        history.capture()

        XCTAssertTrue(history.entries.isEmpty)
    }

    func testUnchangedClipboardIsNotRecordedTwice() {
        copy("once")
        history.capture()
        history.capture()

        XCTAssertEqual(history.entries.count, 1)
    }

    func testRecopyingTheTopClipDoesNotDuplicateIt() {
        copy("same")
        history.capture()
        copy("same")
        history.capture()

        XCTAssertEqual(history.entries.count, 1)
    }

    func testRecopyingAnOlderClipMovesItBackToTheTop() {
        copy("first")
        history.capture()
        copy("second")
        history.capture()
        copy("first")
        history.capture()

        XCTAssertEqual(history.entries.map(\.text), ["first", "second"])
    }

    func testHistoryStopsAtItsLimit() {
        for index in 0..<(ClipboardHistory.limit + 5) {
            copy("clip \(index)")
            history.capture()
        }

        XCTAssertEqual(history.entries.count, ClipboardHistory.limit)
        XCTAssertEqual(history.entries.first?.text, "clip \(ClipboardHistory.limit + 4)")
        XCTAssertEqual(history.entries.last?.text, "clip 5")
    }

    func testCopyBackDoesNotRecordTheClipAgain() {
        copy("first")
        history.capture()
        copy("second")
        history.capture()

        XCTAssertTrue(history.copyBack(history.entries[1]))
        history.capture()

        XCTAssertEqual(history.entries.count, 2)
    }

    func testClearingEmptiesTheHistory() {
        copy("something")
        history.capture()
        history.clear()

        XCTAssertTrue(history.entries.isEmpty)
    }

    func testClearDiscardsACopyNotYetPolled() {
        copy("old")
        history.capture()
        copy("pending")
        history.clear()
        history.capture()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "pending")

        copy("new")
        history.capture()
        XCTAssertEqual(history.entries.map(\.text), ["new"])
    }

    func testClearDiscardsPendingCopyWhenHistoryIsAlreadyEmpty() {
        copy("pending")
        history.clear()
        history.capture()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testPlainTextCleanupKeepsConcealedTextOutOfHistory() {
        let item = NSPasteboardItem()
        item.setString("synthetic private text", forType: .string)
        let marker = NSPasteboardItem()
        marker.setString("1", forType: Self.concealed)
        pasteboard.clearContents()
        pasteboard.writeObjects([item, marker])

        XCTAssertTrue(ClipboardCleaner.makePlainText(pasteboard: pasteboard))
        history.capture()
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertTrue(pasteboard.types?.contains(Self.concealed) == true)
        XCTAssertEqual(pasteboard.string(forType: .string), "synthetic private text")
    }

    func testPlainTextCleanupRemovesRichFormatting() {
        let item = NSPasteboardItem()
        item.setString("ordinary", forType: .string)
        item.setString("<b>ordinary</b>", forType: .html)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        XCTAssertTrue(ClipboardCleaner.makePlainText(pasteboard: pasteboard))
        XCTAssertFalse(pasteboard.types?.contains(.html) == true)
        history.capture()
        XCTAssertEqual(history.entries.map(\.text), ["ordinary"])
    }

    func testRemovingOneClipLeavesTheRest() {
        copy("keep")
        history.capture()
        copy("drop")
        history.capture()

        history.remove(history.entries[0])

        XCTAssertEqual(history.entries.map(\.text), ["keep"])
    }
}

/// Images reach the clipboard in whatever encoding the writer chose, and
/// Switchboard's own screenshot-format setting republishes them as HEIC or
/// JPEG. Every one of those has to survive into the history as PNG.
final class ClipboardImageCaptureTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var history: ClipboardHistory!
    private var spoolDirectory: URL!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("switchboard-image-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        history = ClipboardHistory(pasteboard: pasteboard)
        spoolDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("switchboard-spool-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: spoolDirectory)
        spoolDirectory = nil
        history = nil
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private static func swatch(width: Int, height: Int) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func put(_ data: Data, as type: NSPasteboard.PasteboardType) {
        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private func encoded(_ rep: NSBitmapImageRep, as type: NSBitmapImageRep.FileType) -> Data {
        rep.representation(using: type, properties: [:])!
    }

    func testPNGImageIsRecorded() {
        put(encoded(Self.swatch(width: 40, height: 20), as: .png), as: .png)

        history.capture()

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertTrue(history.entries.first?.isImage == true)
        XCTAssertEqual(history.entries.first?.pixelSize, CGSize(width: 40, height: 20))
    }

    func testJPEGImageIsRecordedAsPNG() {
        put(encoded(Self.swatch(width: 40, height: 20), as: .jpeg),
            as: NSPasteboard.PasteboardType("public.jpeg"))

        history.capture()

        XCTAssertEqual(history.entries.count, 1, "a JPEG screenshot has to reach the history")
        XCTAssertEqual(history.entries.first?.pixelSize, CGSize(width: 40, height: 20))
        // Stored as PNG, so "Copy" puts back something every app can paste.
        XCTAssertEqual(history.entries.first?.imageData?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testHEICImageIsRecordedAsPNG() {
        let png = encoded(Self.swatch(width: 40, height: 20), as: .png)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("could not build the source image")
        }
        let heic = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            heic, UTType.heic.identifier as CFString, 1, nil
        ) else {
            return XCTFail("this machine cannot encode HEIC")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        put(heic as Data, as: NSPasteboard.PasteboardType("public.heic"))
        history.capture()

        XCTAssertEqual(history.entries.count, 1, "a HEIC screenshot has to reach the history")
        XCTAssertEqual(history.entries.first?.pixelSize, CGSize(width: 40, height: 20))
        XCTAssertEqual(history.entries.first?.imageData?.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testScreenshotConversionProducesJPEGAndHEIC() throws {
        for format in [ClipboardImageFormat.jpeg, .heic] {
            let converter = ClipboardImageConverter(pasteboard: pasteboard, spoolDirectory: spoolDirectory)
            converter.configure(enabled: true, format: format.rawValue)
            let converted = expectation(description: format.label)
            converter.onConversion = { result in
                if case .failure(let error) = result { XCTFail(error.localizedDescription) }
                converted.fulfill()
            }
            put(encoded(Self.swatch(width: 40, height: 20), as: .png), as: .png)
            converter.processNewClipboardContents()
            wait(for: [converted], timeout: 5)
            converter.stop()

            let type = NSPasteboard.PasteboardType(format.contentType.identifier)
            let data = try XCTUnwrap(pasteboard.data(forType: type))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, format.contentType.identifier)
            history.capture()
            XCTAssertEqual(history.entries.first?.pixelSize, CGSize(width: 40, height: 20))
        }
    }

    func testScreenshotConversionDoesNotOverwriteANewerCopy() {
        let converter = ClipboardImageConverter(pasteboard: pasteboard, spoolDirectory: spoolDirectory)
        converter.configure(enabled: true, format: "jpg")
        defer { converter.stop() }
        let converted = expectation(description: "stale conversion must not publish")
        converted.isInverted = true
        converter.onConversion = { _ in converted.fulfill() }
        put(encoded(Self.swatch(width: 40, height: 20), as: .png), as: .png)
        converter.processNewClipboardContents()
        pasteboard.clearContents()
        pasteboard.setString("newer copy", forType: .string)
        wait(for: [converted], timeout: 0.3)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer copy")
    }

    /// Drives one conversion to completion and returns the resulting clipboard item.
    private func convertPNGOnClipboard(to format: ClipboardImageFormat,
                                       using converter: ClipboardImageConverter,
                                       size: Int = 40) throws -> NSPasteboardItem {
        let converted = expectation(description: "converted to \(format.label)")
        converter.onConversion = { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            converted.fulfill()
        }
        put(encoded(Self.swatch(width: size, height: size / 2), as: .png), as: .png)
        converter.processNewClipboardContents()
        wait(for: [converted], timeout: 5)
        return try XCTUnwrap(pasteboard.pasteboardItems?.first)
    }

    /// Apps that paste through `NSImage` re-encode to PNG, which is what made
    /// the format setting look broken. The file flavour is what survives.
    func testConversionPublishesAFileInTheChosenFormat() throws {
        for format in [ClipboardImageFormat.jpeg, .heic] {
            let converter = ClipboardImageConverter(pasteboard: pasteboard,
                                                    spoolDirectory: spoolDirectory)
            defer { converter.stop() }
            converter.configure(enabled: true, format: format.rawValue)
            let item = try convertPNGOnClipboard(to: format, using: converter)

            let urlString = try XCTUnwrap(item.string(forType: .fileURL),
                                          "\(format.label) needs a pasteable file")
            let file = try XCTUnwrap(URL(string: urlString))
            XCTAssertEqual(file.pathExtension, format.rawValue)
            XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL,
                           spoolDirectory.standardizedFileURL)

            let onDisk = try Data(contentsOf: file)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(onDisk as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, format.contentType.identifier,
                           "the file has to really be \(format.label), not just named that way")
            let type = NSPasteboard.PasteboardType(format.contentType.identifier)
            XCTAssertEqual(onDisk, item.data(forType: type),
                           "the file and the image flavour must be the same bytes")
        }
    }

    /// A file URL transcodes to text on some pasteboards. If that leaked, every
    /// converted screenshot would land in the history as a path instead.
    func testConvertedScreenshotStillRecordsAsAnImage() throws {
        let converter = ClipboardImageConverter(pasteboard: pasteboard,
                                                spoolDirectory: spoolDirectory)
        defer { converter.stop() }
        converter.configure(enabled: true, format: "jpg")
        _ = try convertPNGOnClipboard(to: .jpeg, using: converter)

        XCTAssertNil(pasteboard.string(forType: .string))
        history.capture()
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertTrue(history.entries.first?.isImage == true)
        XCTAssertEqual(history.entries.first?.pixelSize, CGSize(width: 40, height: 20))
    }

    func testSpooledFilesAreCappedAndKeepTheNewest() throws {
        let converter = ClipboardImageConverter(pasteboard: pasteboard,
                                                spoolDirectory: spoolDirectory)
        defer { converter.stop() }
        converter.configure(enabled: true, format: "jpg")

        var newest: URL?
        for round in 0..<(ClipboardImageConverter.spooledFileLimit + 3) {
            // Distinct sizes keep each conversion a distinct clipboard write.
            let item = try convertPNGOnClipboard(to: .jpeg, using: converter, size: 40 + round * 2)
            newest = URL(string: try XCTUnwrap(item.string(forType: .fileURL)))
        }

        let remaining = try FileManager.default.contentsOfDirectory(
            at: spoolDirectory, includingPropertiesForKeys: nil
        )
        XCTAssertLessThanOrEqual(remaining.count, ClipboardImageConverter.spooledFileLimit)
        let newestFile = try XCTUnwrap(newest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newestFile.path),
                      "the file the clipboard points at must never be pruned")
    }

    func testStyledTextWithAnImagePreviewIsRecordedAsText() {
        let item = NSPasteboardItem()
        item.setString("styled", forType: .string)
        item.setData(encoded(Self.swatch(width: 10, height: 10), as: .tiff), forType: .tiff)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        history.capture()

        XCTAssertEqual(history.entries.first?.text, "styled")
        XCTAssertFalse(history.entries.first?.isImage == true)
    }
}

/// A private marker on the clipboard is the difference between a history and
/// a leak, so every marker Switchboard knows about gets its own case.
final class ClipboardExclusionTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var history: ClipboardHistory!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("switchboard-exclusion-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        history = ClipboardHistory(pasteboard: pasteboard)
    }

    override func tearDown() {
        history = nil
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func captureSecret(markedWith marker: String) {
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        XCTAssertTrue(item.setString("1", forType: NSPasteboard.PasteboardType(marker)),
                      "\(marker) has to be writable as a UTI for this test to mean anything")
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        history.capture()
    }

    func testEveryKnownPrivateMarkerSuppressesTheClip() {
        let markers = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "de.petermaurer.TransientPasteboardType",
            "com.agilebits.onepassword",
            "net.antelle.keeweb",
            "com.typeit4me.clipping"
        ]

        for marker in markers {
            captureSecret(markedWith: marker)
            XCTAssertTrue(history.entries.isEmpty, "\(marker) has to suppress the clip")
        }
    }

    /// "Pasteboard generator type" is not a valid UTI, so a tool can only
    /// publish it through the legacy `declareTypes:` API. That leaves it on
    /// the pasteboard but on none of its items -- reading item types alone
    /// misses it entirely, which is what this exclusion used to do.
    func testLegacyGeneratorMarkerDeclaredOnThePasteboardSuppressesTheClip() {
        let marker = NSPasteboard.PasteboardType("Pasteboard generator type")
        pasteboard.declareTypes([marker, .string], owner: nil)
        pasteboard.setString("1", forType: marker)
        pasteboard.setString("hunter2", forType: .string)

        XCTAssertFalse((pasteboard.pasteboardItems ?? []).contains { $0.types.contains(marker) },
                       "the premise of this test is that the marker is not on any item")

        history.capture()

        XCTAssertTrue(history.entries.isEmpty)
    }

    func testAnUnknownMarkerStillRecordsTheClip() {
        captureSecret(markedWith: "com.example.some-other-type")

        XCTAssertEqual(history.entries.map(\.text), ["hunter2"])
    }
}
