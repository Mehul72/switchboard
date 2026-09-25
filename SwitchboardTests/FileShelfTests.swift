import AppKit
import XCTest

@MainActor
final class FileShelfTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String = "Report.txt") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("Original contents".utf8).write(to: url)
        return url
    }

    func testDuplicateDropsKeepOneReferenceAndDoNotChangeOriginal() throws {
        let url = try file()
        let shelf = FileShelf()
        XCTAssertTrue(shelf.add([url, url]))
        XCTAssertTrue(shelf.add([url]))
        XCTAssertEqual(shelf.files.count, 1)
        shelf.clear()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Original contents")
    }

    func testRemoveOnlyRemovesReferenceAndUpdatesCount() throws {
        let url = try file()
        let shelf = FileShelf()
        var counts: [Int] = []
        shelf.onCountChange = { counts.append($0) }
        shelf.add([url])
        shelf.remove(try XCTUnwrap(shelf.files.first).id)
        XCTAssertTrue(shelf.files.isEmpty)
        XCTAssertEqual(counts, [1, 0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLimitNeverEvictsFilesAlreadyHeld() throws {
        let urls = try (0...FileShelf.limit).map { try file("\($0).txt") }
        let shelf = FileShelf()
        shelf.add(urls)
        XCTAssertEqual(shelf.files.map(\.url), Array(urls.prefix(FileShelf.limit)))
        XCTAssertEqual(shelf.notice?.isError, true)
        XCTAssertTrue(shelf.add([urls[0]]))
        XCTAssertEqual(shelf.files.count, FileShelf.limit)
    }

    func testFolderAcceptedButMissingRemoteAndVolumeRootRejected() throws {
        let shelf = FileShelf()
        XCTAssertTrue(shelf.add([directory]))
        XCTAssertFalse(shelf.add([directory.appendingPathComponent("missing"),
                                   URL(string: "https://example.com/file")!,
                                   URL(string: "file://remote.invalid/file")!,
                                   URL(fileURLWithPath: "/")]))
        XCTAssertEqual(shelf.files.count, 1)
        XCTAssertEqual(shelf.notice?.isError, true)
    }

    func testEmptyDropLeavesExistingShelfAlone() throws {
        let shelf = FileShelf()
        shelf.add([try file()])
        XCTAssertFalse(shelf.add([]))
        XCTAssertEqual(shelf.files.count, 1)
    }

    func testBookmarkFollowsRenamedOriginal() throws {
        let url = try file()
        let shelf = FileShelf()
        shelf.add([url])
        let id = try XCTUnwrap(shelf.files.first).id
        let renamed = directory.appendingPathComponent("Renamed.txt")
        try FileManager.default.moveItem(at: url, to: renamed)
        XCTAssertEqual(shelf.availableURL(for: id), renamed)
        XCTAssertEqual(shelf.files.first?.name, "Renamed.txt")
    }

    func testDeletedFileRemainsVisibleAsUnavailable() throws {
        let url = try file()
        let shelf = FileShelf()
        shelf.add([url])
        let id = try XCTUnwrap(shelf.files.first).id
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(shelf.availableURL(for: id))
        XCTAssertEqual(shelf.files.count, 1)
        XCTAssertEqual(shelf.files.first?.isAvailable, false)
        XCTAssertEqual(shelf.notice?.isError, true)
    }

    func testCopyWritesFileURLWithoutReplacingContents() throws {
        let url = try file("Spaces & quotes ' $.txt")
        let shelf = FileShelf()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        shelf.add([url])
        shelf.copy(try XCTUnwrap(shelf.files.first).id, to: pasteboard)
        XCTAssertEqual(FileShelf.readFiles(from: pasteboard), [url])
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Original contents")
    }

    func testTextThatLooksLikeAPathIsNotAFileDrop() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("/etc/hosts", forType: .string)
        XCTAssertTrue(FileShelf.readFiles(from: pasteboard).isEmpty)
    }
}
