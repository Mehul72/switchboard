import AppKit
import XCTest

@MainActor
final class ShelfVolumesTests: XCTestCase {
    private let disk = ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Test Drive"), name: "Test Drive", uuid: "test")

    func testProtectedUnknownAndNetworkVolumesCannotBeEjected() {
        XCTAssertFalse(ShelfVolume.canEject(isInternal: true, isEjectable: false, isRemovable: false, isLocal: true, isBrowsable: true, path: "/Volumes/Data"))
        XCTAssertFalse(ShelfVolume.canEject(isInternal: false, isEjectable: true, isRemovable: true, isLocal: true, isBrowsable: true, path: "/"))
        XCTAssertFalse(ShelfVolume.canEject(isInternal: false, isEjectable: true, isRemovable: true, isLocal: true, isBrowsable: true, path: "/System/Volumes/Data"))
        XCTAssertFalse(ShelfVolume.canEject(isInternal: nil, isEjectable: nil, isRemovable: nil, isLocal: true, isBrowsable: true, path: "/Volumes/Unknown"))
        XCTAssertFalse(ShelfVolume.canEject(isInternal: false, isEjectable: true, isRemovable: false, isLocal: false, isBrowsable: true, path: "/Volumes/Server"))
        XCTAssertTrue(ShelfVolume.canEject(isInternal: false, isEjectable: false, isRemovable: false, isLocal: true, isBrowsable: true, path: "/Volumes/SSD"))
        XCTAssertTrue(ShelfVolume.canEject(isInternal: nil, isEjectable: true, isRemovable: false, isLocal: true, isBrowsable: true, path: "/Volumes/Installer"))
    }

    func testHiddenToolMountsCannotBeEjected() {
        XCTAssertFalse(ShelfVolume.canEject(isInternal: nil, isEjectable: true, isRemovable: true, isLocal: true, isBrowsable: false,
                                            path: "/Library/Developer/CoreSimulator/Volumes/iOS_23F77"))
        XCTAssertFalse(ShelfVolume.canEject(isInternal: nil, isEjectable: true, isRemovable: true, isLocal: true, isBrowsable: nil,
                                            path: "/Volumes/Unknown"))
    }

    func testMixedDropSeparatesVolumeRootsFromFilesInsideThem() {
        let file = disk.url.appendingPathComponent("Report.pdf")
        let drop = ShelfDrop(urls: [disk.url, file, disk.url, file], volumes: [disk])
        XCTAssertEqual(drop.volumes, [disk])
        XCTAssertEqual(drop.files, [file])
    }

    func testDownloadedImageIsAFileAndCanFindItsMountedVolumes() {
        let image = URL(fileURLWithPath: "/tmp/Installer.dmg")
        var mounted = disk
        mounted.imageURL = image
        let store = ShelfVolumes(load: { $0(.success([mounted])) }, eject: { _, _ in XCTFail("Must not eject on discovery") })
        store.refresh()
        let drop = ShelfDrop(urls: [image], volumes: store.volumes)
        XCTAssertEqual(drop.files, [image])
        XCTAssertTrue(drop.volumes.isEmpty)
        XCTAssertEqual(store.mountedImages(for: image), [mounted])
    }

    func testParsesMultipleMountedPartitionsAndIgnoresNonMountedEntities() throws {
        let plist: [String: Any] = ["images": [
            ["image-path": "/tmp/Installer ' $.dmg", "system-entities": [
                ["dev-entry": "/dev/disk9"],
                ["dev-entry": "/dev/disk9s1"],
                ["mount-point": "/Volumes/Installer"],
                ["mount-point": "/Volumes/Extras"]]],
            ["image-path": "/tmp/Unmounted.dmg", "system-entities": []]
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let mounts = try DiskImageMounts.parse(data)
        XCTAssertEqual(mounts.count, 2)
        XCTAssertEqual(mounts[URL(fileURLWithPath: "/Volumes/Extras")],
                       DiskImageMount(source: URL(fileURLWithPath: "/tmp/Installer ' $.dmg"), device: "/dev/disk9"))
        XCTAssertThrowsError(try DiskImageMounts.parse(Data("invalid".utf8)))
        let empty = try PropertyListSerialization.data(fromPropertyList: ["images": []], format: .xml, options: 0)
        XCTAssertTrue(try DiskImageMounts.parse(empty).isEmpty)
    }

    func testAPFSImageDetachesItsOwnDiskNotTheSynthesizedContainer() throws {
        let plist: [String: Any] = ["images": [["image-path": "/tmp/App.dmg", "system-entities": [
            ["dev-entry": "/dev/disk10"], ["dev-entry": "/dev/disk10s1"],
            ["dev-entry": "/dev/disk11"], ["dev-entry": "/dev/disk11s1", "mount-point": "/Volumes/App"]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertEqual(try DiskImageMounts.parse(data)[URL(fileURLWithPath: "/Volumes/App")]?.device, "/dev/disk10")
    }

    func testOnlyBareWholeDisksCanBeDetached() {
        XCTAssertTrue(DiskImageMounts.isWholeDisk("/dev/disk10"))
        for unsafe in ["/dev/disk10s1", "disk10", "/dev/disk", "/dev/disk1 -force", "/dev/disk1\n", "/Volumes/App", ""] {
            XCTAssertFalse(DiskImageMounts.isWholeDisk(unsafe), unsafe)
        }
        XCTAssertThrowsError(try DiskImageMounts.detach("-force"))
    }

    func testImageWithoutWholeDiskEntryIsNotLinked() throws {
        let plist: [String: Any] = ["images": [["image-path": "/tmp/Odd.dmg", "system-entities": [
            ["dev-entry": "/dev/disk12s1", "mount-point": "/Volumes/Odd"]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertTrue(try DiskImageMounts.parse(data).isEmpty)
    }

    private func shelvedFile(_ name: String) throws -> (FileShelf, ShelfFile) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfDelete-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try Data("example".utf8).write(to: url)
        let shelf = FileShelf()
        shelf.add([url])
        return (shelf, try XCTUnwrap(shelf.files.first))
    }

    func testCommandDeleteOnDiskEjectsOnceAndKeepsItSelected() {
        var requests: [ShelfVolume] = []
        let volumes = ShelfVolumes(load: { [disk] in $0(.success([disk])) }, eject: { volume, _ in requests.append(volume) })
        volumes.refresh()
        let selection = ShelfSelection.volume(disk.id)
        XCTAssertEqual(selection.performDelete(shelf: FileShelf(), volumes: volumes), selection)
        XCTAssertEqual(selection.performDelete(shelf: FileShelf(), volumes: volumes), selection)
        XCTAssertEqual(requests, [disk], "A second press while ejecting must not queue another eject")
    }

    func testCommandDeleteOnShelvedMountedImageEjectsItAndKeepsTheFile() throws {
        let (shelf, file) = try shelvedFile("Installer.dmg")
        var mounted = disk
        mounted.imageURL = file.url
        var requests: [ShelfVolume] = []
        let volumes = ShelfVolumes(load: { $0(.success([mounted])) }, eject: { volume, _ in requests.append(volume) })
        volumes.refresh()
        XCTAssertEqual(ShelfSelection.file(file.id).performDelete(shelf: shelf, volumes: volumes), .file(file.id))
        XCTAssertEqual(requests, [mounted])
        XCTAssertEqual(shelf.files.map(\.id), [file.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testCommandDeleteOnPlainFileOnlyRemovesTheReference() throws {
        let (shelf, file) = try shelvedFile("Notes.txt")
        let volumes = ShelfVolumes(load: { [disk] in $0(.success([disk])) }, eject: { _, _ in XCTFail("Must not eject") })
        volumes.refresh()
        XCTAssertNil(ShelfSelection.file(file.id).performDelete(shelf: shelf, volumes: volumes))
        XCTAssertTrue(shelf.files.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path), "Original must stay in place")
    }

    func testFailedEjectReportsToItsCallerButSuccessDoesNot() {
        var fail = true
        let volumes = ShelfVolumes(load: { [disk] in $0(.success([disk])) }, eject: { _, callback in
            callback(fail ? .failure(NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))) : .success(()))
        })
        volumes.refresh()
        var failures = 0
        volumes.eject(disk, failed: { failures += 1 })
        XCTAssertEqual(failures, 1)
        fail = false
        volumes.eject(disk, failed: { failures += 1 })
        XCTAssertEqual(failures, 1)
    }

    func testCommandDeleteOnStaleSelectionDoesNothing() {
        let volumes = ShelfVolumes(load: { $0(.success([])) }, eject: { _, _ in XCTFail("Must not eject") })
        volumes.refresh()
        XCTAssertNil(ShelfSelection.volume(disk.id).performDelete(shelf: FileShelf(), volumes: volumes))
        XCTAssertNil(ShelfSelection.file(UUID()).performDelete(shelf: FileShelf(), volumes: volumes))
    }

    func testDrivesStayListedWhenImageDiscoveryFails() {
        let linked = NativeShelfVolumes.linkingImages([disk]) { throw CocoaError(.executableRuntimeMismatch) }
        XCTAssertEqual(linked, [disk])
        XCTAssertNil(linked.first?.imageURL)
    }

    func testMountedImageIsLinkedToItsSource() {
        let image = URL(fileURLWithPath: "/tmp/Installer.dmg")
        let linked = NativeShelfVolumes.linkingImages([disk]) {
            [self.disk.url: DiskImageMount(source: image, device: "/dev/disk10")]
        }
        XCTAssertEqual(linked.first?.imageURL, image)
        XCTAssertEqual(linked.first?.imageDevice, "/dev/disk10")
    }

    func testImageAssociationResolvesSymlinkedParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfImage-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appendingPathComponent("image.dmg")
        try Data().write(to: real)
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        var mounted = disk
        mounted.imageURL = real
        let store = ShelfVolumes(load: { $0(.success([mounted])) }, eject: { _, _ in })
        store.refresh()
        XCTAssertEqual(store.mountedImages(for: alias.appendingPathComponent("image.dmg")), [mounted])
    }

    func testRepeatedEjectStaysPendingUntilNativeOperationCompletes() {
        var requests = 0
        var completion: ((Result<Void, Error>) -> Void)?
        var connected = [disk]
        let store = ShelfVolumes(load: { $0(.success(connected)) }, eject: { _, callback in
            requests += 1
            completion = callback
        })
        store.refresh()
        store.eject(disk)
        store.eject(disk)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.ejecting, [disk.id])
        XCTAssertEqual(store.volumes, [disk])
        XCTAssertNil(store.notice)
        connected = []
        completion?(.success(()))
        XCTAssertTrue(store.volumes.isEmpty)
        XCTAssertTrue(store.ejecting.isEmpty)
        XCTAssertEqual(store.notice?.isError, false)
    }

    func testBusyDiskRemainsAndCanBeRetried() {
        var requests = 0
        let store = ShelfVolumes(load: { [disk] in $0(.success([disk])) }, eject: { _, callback in
            requests += 1
            callback(.failure(NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))))
        })
        store.refresh()
        store.eject(disk)
        XCTAssertEqual(store.volumes, [disk])
        XCTAssertTrue(store.ejecting.isEmpty)
        XCTAssertEqual(store.notice?.isError, true)
        store.eject(disk)
        XCTAssertEqual(requests, 2)
    }

    func testStaleDiskCannotEjectReplacementAtSamePath() {
        let replacement = ShelfVolume(url: disk.url, name: disk.name, uuid: "replacement")
        let store = ShelfVolumes(load: { $0(.success([replacement])) }, eject: { _, _ in XCTFail("Stale disk must not eject") })
        store.refresh()
        store.eject(disk)
        XCTAssertTrue(store.ejecting.isEmpty)
        XCTAssertEqual(store.volumes, [replacement])
    }

    func testDiscoveryFailureIsVisibleAndRefreshRecovers() {
        var fail = true
        let store = ShelfVolumes(load: { [disk] callback in
            callback(fail ? .failure(CocoaError(.fileReadUnknown)) : .success([disk]))
        }, eject: { _, _ in })
        store.refresh()
        XCTAssertEqual(store.notice?.isError, true)
        XCTAssertFalse(store.isRefreshing)
        fail = false
        store.refresh()
        XCTAssertEqual(store.volumes, [disk])
    }

    func testMountNotificationsDuringRefreshAreCoalesced() {
        var requests = 0
        var callback: ((Result<[ShelfVolume], Error>) -> Void)?
        let store = ShelfVolumes(load: { completion in requests += 1; callback = completion }, eject: { _, _ in })
        store.refresh()
        store.refresh()
        store.refresh()
        XCTAssertEqual(requests, 1)
        callback?(.success([]))
        XCTAssertEqual(requests, 2)
        callback?(.success([disk]))
        XCTAssertEqual(store.volumes, [disk])
        XCTAssertFalse(store.isRefreshing)
    }
}
