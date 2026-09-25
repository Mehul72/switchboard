import AppKit
import SwiftUI
import XCTest

@MainActor
final class ShelfDraggingTests: XCTestCase {
    func testHoverOnlyPreviewsAndDropIsExplicit() throws {
        let url = URL(fileURLWithPath: "/Volumes/Example")
        let info = TestShelfDrag(urls: [url])
        let view = ShelfDropHostingView(rootView: Text("Eject"))
        var hovered: [URL] = []
        var requests = 0
        view.onHover = { hovered = $0 }
        view.onDrop = { urls in
            XCTAssertEqual(urls, [url])
            requests += 1
            return true
        }
        XCTAssertEqual(view.draggingEntered(info), .copy)
        XCTAssertEqual(view.draggingUpdated(info), .copy)
        XCTAssertEqual(hovered, [url])
        XCTAssertEqual(requests, 0)
        view.draggingExited(info)
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(view.prepareForDragOperation(info))
        XCTAssertTrue(view.performDragOperation(info))
        XCTAssertEqual(requests, 1)
    }

    func testDropRevalidatesPayloadAndRefusesMoveOnlySources() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let info = TestShelfDrag(urls: [first])
        let view = ShelfDropHostingView(rootView: Text("Target"))
        view.accepts = { $0 == [first] }
        view.onDrop = { _ in XCTFail("Changed payload must not execute the action"); return true }
        XCTAssertEqual(view.draggingEntered(info), .copy)
        info.draggingPasteboard.clearContents()
        info.draggingPasteboard.writeObjects([URL(fileURLWithPath: "/tmp/different") as NSURL])
        XCTAssertFalse(view.performDragOperation(info))
        info.draggingPasteboard.clearContents()
        info.draggingPasteboard.writeObjects([first as NSURL])
        info.draggingSourceOperationMask = .move
        XCTAssertEqual(view.draggingEntered(info), [])
        XCTAssertFalse(view.prepareForDragOperation(info))
        XCTAssertFalse(view.performDragOperation(info))
    }

    func testClickSelectsButPressWithoutMouseDownDoesNot() throws {
        let view = ShelfFileDragView(rootView: Text("Tile"))
        view.frame = NSRect(x: 0, y: 0, width: 60, height: 60)
        var clicks = 0
        view.onClick = { clicks += 1 }
        func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 30, y: 30), modifierFlags: [],
                                              timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                              clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try mouse(.leftMouseDown))
        view.mouseUp(with: try mouse(.leftMouseUp))
        XCTAssertEqual(clicks, 1)
        view.mouseUp(with: try mouse(.leftMouseUp))
        XCTAssertEqual(clicks, 1, "A release without its own press is not a click")
    }

    func testDroppingOnPanelHoldsFilesButNeverEjectsDisks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfDrop-\(UUID()).txt")
        try Data("example".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let disk = ShelfVolume(url: URL(fileURLWithPath: "/Volumes/Example"), name: "Example", uuid: "id")
        let volumes = ShelfVolumes(load: { $0(.success([disk])) }, eject: { _, _ in XCTFail("Panel is not an eject target") })
        volumes.refresh()
        let shelf = FileShelf()
        let controller = FileShelfController(shelf: shelf, volumes: volumes)
        XCTAssertTrue(controller.accept([url, disk.url]))
        XCTAssertEqual(shelf.files.map(\.url), [url])
        XCTAssertEqual(volumes.volumes, [disk])
        XCTAssertFalse(controller.accept([disk.url]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPanelGetsKeyboardFocusAndEscapeClosesIt() throws {
        try withRunningApplication {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            defer { NSStatusBar.system.removeStatusItem(item) }
            let button = try XCTUnwrap(item.button)
            let volumes = ShelfVolumes(load: { $0(.success([])) }, eject: { _, _ in })
            let controller = FileShelfController(shelf: FileShelf(), volumes: volumes)
            defer { controller.close() }
            controller.show(relativeTo: button)
            let panel = try XCTUnwrap(controller.panel)
            XCTAssertTrue(panel.isVisible)
            XCTAssertTrue(panel.isKeyWindow)
            XCTAssertEqual(panel.frame.width, FileShelfController.width)
            let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                       timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                                       characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                       isARepeat: false, keyCode: 53))
            NSApp.sendEvent(escape)
            XCTAssertFalse(controller.isVisible)
            XCTAssertTrue(controller.drag.urls.isEmpty)
        }
    }

    func testRepeatedDragTriggersKeepPanelAndDiscoveryStable() throws {
        try withRunningApplication {
            var discoveries = 0
            let volumes = ShelfVolumes(load: { callback in discoveries += 1; callback(.success([])) }, eject: { _, _ in })
            let controller = FileShelfController(shelf: FileShelf(), volumes: volumes)
            defer { controller.close() }
            let urls = [URL(fileURLWithPath: "/tmp/held-file")]
            let pointer = NSEvent.mouseLocation
            controller.show(beside: pointer, incoming: urls)
            let original = try XCTUnwrap(controller.panel)
            for _ in 0..<10 { controller.show(beside: pointer, incoming: urls) }
            XCTAssertTrue(controller.panel === original)
            XCTAssertFalse(original.frame.contains(pointer))
            XCTAssertFalse(original.isKeyWindow, "Taking focus mid-drag would pull the user out of the source app")
            XCTAssertEqual(discoveries, 1)
            XCTAssertEqual(controller.drag.urls, urls)
        }
    }

    private func withRunningApplication(_ body: @escaping () throws -> Void) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var failure: Error?
        let stop = {
            app.stop(nil)
            let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
            app.postEvent(wake, atStart: true)
        }
        let execute = {
            do { try body() } catch { failure = error }
            stop()
        }
        var observer: NSObjectProtocol?
        if app.isActive {
            DispatchQueue.main.async { execute() }
        } else {
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                               object: app, queue: .main) { _ in
                DispatchQueue.main.async { execute() }
            }
            DispatchQueue.main.async { app.activate(ignoringOtherApps: true) }
        }
        let timeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            XCTFail("The shelf test application did not become active.")
            stop()
        }
        defer {
            timeout.invalidate()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
        app.run()
        if let failure { throw failure }
    }
}

@MainActor
private final class TestShelfDrag: NSObject, NSDraggingInfo {
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    init(urls: [URL]) {
        super.init()
        draggingPasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}

    deinit { draggingPasteboard.releaseGlobally() }
}
