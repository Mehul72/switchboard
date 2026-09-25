import AppKit
import Carbon.HIToolbox
import XCTest

final class FinderEjectShortcutTests: XCTestCase {
    private let drive = ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Studio SSD"), name: "Studio SSD", uuid: "drive")
    private let image = ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Installer"), name: "Installer", uuid: "image",
                                    imageURL: URL(fileURLWithPath: "/tmp/Installer.dmg"), imageDevice: "/dev/disk10")

    func testOnlyPlainCommandDeleteCounts() {
        let delete = UInt16(kVK_Delete)
        XCTAssertTrue(FinderEjectShortcut.isCommandDelete(keyCode: delete, modifiers: .command))
        XCTAssertTrue(FinderEjectShortcut.isCommandDelete(keyCode: delete, modifiers: [.command, .capsLock]))
        XCTAssertFalse(FinderEjectShortcut.isCommandDelete(keyCode: delete, modifiers: []))
        XCTAssertFalse(FinderEjectShortcut.isCommandDelete(keyCode: delete, modifiers: [.command, .shift]),
                       "Command-Shift-Delete empties the Trash in Finder")
        XCTAssertFalse(FinderEjectShortcut.isCommandDelete(keyCode: delete, modifiers: [.command, .option]))
        XCTAssertFalse(FinderEjectShortcut.isCommandDelete(keyCode: UInt16(kVK_ForwardDelete), modifiers: .command))
    }

    func testSelectedDisksAreEjectedWhateverTheURLSpelling() {
        let selected = [URL(fileURLWithPath: "/Volumes/Studio SSD/"), URL(string: "file:///Volumes/Installer/")!]
        XCTAssertEqual(FinderEjectShortcut.volumesToEject(selected: selected, ejectable: [drive, image]), [drive, image])
    }

    func testAnyFileInTheSelectionLeavesItToFinder() {
        let file = URL(fileURLWithPath: "/tmp/Installer.dmg")
        XCTAssertTrue(FinderEjectShortcut.volumesToEject(selected: [file], ejectable: [drive, image]).isEmpty,
                      "A selected disk image file goes to the Trash, not an eject")
        XCTAssertTrue(FinderEjectShortcut.volumesToEject(selected: [drive.url, file], ejectable: [drive, image]).isEmpty)
        XCTAssertTrue(FinderEjectShortcut.volumesToEject(selected: [drive.url.appendingPathComponent("Report.pdf")],
                                                         ejectable: [drive]).isEmpty)
    }

    func testNothingSelectedOrProtectedDiskEjectsNothing() {
        XCTAssertTrue(FinderEjectShortcut.volumesToEject(selected: [], ejectable: [drive]).isEmpty)
        XCTAssertTrue(FinderEjectShortcut.volumesToEject(selected: [URL(fileURLWithPath: "/")], ejectable: [drive]).isEmpty)
    }

    func testVolumesOfOneImageAreEjectedOnce() {
        let second = ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Installer Extras"), name: "Extras", uuid: "extras",
                                 imageURL: image.imageURL, imageDevice: image.imageDevice)
        let targets = FinderEjectShortcut.volumesToEject(selected: [image.url, second.url, image.url],
                                                         ejectable: [image, second])
        XCTAssertEqual(targets, [image])
    }
}
