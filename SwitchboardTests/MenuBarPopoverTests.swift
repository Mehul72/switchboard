import AppKit
import SwiftUI
import XCTest

@MainActor
final class MenuBarPopoverTests: XCTestCase {
    private func makePopover() -> NSPopover {
        let popover = MenuBarPopover()
        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: Theme.canvas.frame(width: 200, height: 200))
        host.sizingOptions = []
        host.view.frame.size = NSSize(width: 200, height: 200)
        popover.contentViewController = host
        return popover
    }

    func testVisibleCanvasChangesWithAppearanceAndWhenReopened() throws {
        try withRunningApplication {
            let original = NSApp.appearance
            defer { NSApp.appearance = original }
            let (anchorWindow, button) = try self.makeAnchor()
            defer { anchorWindow.close() }
            let popover = self.makePopover()
            defer { popover.close() }
            // Like the menu bar, the anchor keeps its own appearance, so each step
            // fails if the popover follows its anchor instead of the app.
            let setAppearance = { (name: NSAppearance.Name?) in
                NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
                let appIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                anchorWindow.appearance = NSAppearance(named: appIsDark ? .aqua : .darkAqua)
            }
            setAppearance(.aqua)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            for (name, expected) in [(NSAppearance.Name.aqua, 0xF3F5F8), (.darkAqua, 0x202226),
                                     (.aqua, 0xF3F5F8), (.darkAqua, 0x202226)] {
                setAppearance(name)
                try self.assertCanvas(popover, expected: expected)
            }
            setAppearance(nil)
            let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            try self.assertCanvas(popover, expected: systemIsDark ? 0x202226 : 0xF3F5F8)
            popover.close()
            setAppearance(.aqua)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            try self.assertCanvas(popover, expected: 0xF3F5F8)
        }
    }

    func testOutsideClicksDismissEvenWhenAutomaticClosingIsProtected() throws {
        try withRunningApplication {
            let (anchorWindow, button) = try self.makeAnchor()
            defer { anchorWindow.close() }
            let popover = self.makePopover()
            let protection = ProtectedPopoverDelegate()
            popover.delegate = protection
            defer { popover.close() }
            let outside = NSPanel(contentRect: NSRect(x: 100, y: 300, width: 150, height: 100),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            outside.isReleasedWhenClosed = false
            let target = ClickTarget(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
            outside.contentView = target
            outside.orderFrontRegardless()
            defer { outside.close() }

            for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                XCTAssertTrue(popover.isShown)
                popover.performClose(nil)
                XCTAssertTrue(popover.isShown, "Automatic restart protection stays intact")
                NSApp.sendEvent(try self.click(type, in: outside))
                XCTAssertFalse(popover.isShown, "An explicit outside click must always dismiss: \(type)")
            }
            XCTAssertEqual(target.clicks, 3, "Dismissal must not consume the original click")
        }
    }

    func testClicksWithinPopoverAnchorAndChildWindowsStayOpen() throws {
        try withRunningApplication {
            let (anchorWindow, button) = try self.makeAnchor()
            defer { anchorWindow.close() }
            let popover = self.makePopover()
            defer { popover.close() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            let window = try XCTUnwrap(popover.contentViewController?.view.window)
            let anchor = try XCTUnwrap(button.window)
            NSApp.sendEvent(try self.click(.leftMouseDown, in: window))
            XCTAssertTrue(popover.isShown)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            NSApp.postEvent(try self.click(.leftMouseUp, in: anchor, at: point), atStart: true)
            NSApp.sendEvent(try self.click(.leftMouseDown, in: anchor, at: point))
            XCTAssertTrue(popover.isShown, "The anchor button's action must handle its own toggle")
            let child = NSPanel(contentRect: NSRect(x: 100, y: 300, width: 120, height: 80),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            child.isReleasedWhenClosed = false
            window.addChildWindow(child, ordered: .above)
            defer { window.removeChildWindow(child); child.close() }
            NSApp.sendEvent(try self.click(.leftMouseDown, in: child))
            XCTAssertTrue(popover.isShown, "Attached pickers belong to the panel")
        }
    }

    /// A click on a menu bar item does not activate the app, so one held for
    /// activation only ever came back through the 0.3 second fallback.
    func testAnchorClickIsNotHeldWhileTheAppIsInactive() throws {
        try withRunningApplication {
            let (anchorWindow, button) = try self.makeAnchor()
            defer { anchorWindow.close() }
            let toggle = ActionCounter()
            button.target = toggle
            button.action = #selector(ActionCounter.fire)
            let popover = MenuBarPopover()
            popover.animates = false
            popover.contentViewController = NSHostingController(rootView: Theme.canvas.frame(width: 200, height: 200))
            defer { popover.close() }
            popover.isAppActive = { false }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            let anchor = try XCTUnwrap(button.window)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)

            NSApp.postEvent(try self.click(.leftMouseUp, in: anchor, at: point), atStart: true)
            NSApp.sendEvent(try self.click(.leftMouseDown, in: anchor, at: point))

            XCTAssertEqual(toggle.count, 1, "the click reached the menu bar item at once")
        }
    }

    /// The hand-over for real: this app holds the front, gives it to another
    /// app, and opens the panel on macOS's own reports of the change. The
    /// stand-ins in FrontHandoverTests cannot show that those reports arrive.
    func testAPanelOpenedOnceTheFrontIsHandedBackStaysOpen() throws {
        let appToHandFrontTo = try XCTUnwrap(NSWorkspace.shared.menuBarOwningApplication)
        try XCTSkipIf(appToHandFrontTo == .current, "no other app to hand the front to")
        try withRunningApplication(untilFinished: { finish in
            let (anchorWindow, button) = try self.makeAnchor()
            let popover = self.makePopover()
            let handover = FrontHandover()
            handover.fullScreenApp = { _ in appToHandFrontTo }
            XCTAssertTrue(handover.isFrontApp(), "the test app must hold the front for there to be anything to hand back")

            handover.handBack(on: nil) {
                XCTAssertFalse(handover.isFrontApp(), "the front went back before the panel opened")
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                XCTAssertTrue(popover.isShown)
                // Many times longer than AppKit takes to act on a change it had not finished with.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    XCTAssertTrue(popover.isShown, "losing the front must not take the panel with it")
                    popover.close()
                    anchorWindow.close()
                    finish()
                }
            }
        })
    }

    /// Never a real status item: a popover opened from one asks macOS 27 to hold the
    /// menu bar open, and removing the item a moment later left the menu bar stuck
    /// over full-screen apps until MenuBarAgent restarted.
    private func makeAnchor() throws -> (NSWindow, NSButton) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 600, width: 60, height: 24),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let button = NSButton(title: "T", target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 0, width: 60, height: 24)
        window.contentView?.addSubview(button)
        window.orderFrontRegardless()
        let deadline = Date().addingTimeInterval(2)
        while (!window.isVisible || button.visibleRect.isEmpty), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(window.isVisible && !button.visibleRect.isEmpty, "The anchor must be laid out before showing its popover")
        return (window, button)
    }

    private func canvasHex(_ popover: NSPopover) throws -> Int {
        let view = try XCTUnwrap(popover.contentViewController?.view)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        return Int((color.redComponent * 255).rounded()) << 16
            | Int((color.greenComponent * 255).rounded()) << 8 | Int((color.blueComponent * 255).rounded())
    }

    private func assertCanvas(_ popover: NSPopover, expected: Int,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try canvasHex(popover)
        let view = try XCTUnwrap(popover.contentViewController?.view)
        XCTAssertEqual(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                       NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), file: file, line: line)
        // AppKit's popover material slightly tints a cached view snapshot.
        // The tolerance still rejects an unchanged canvas when switching either direction.
        for shift in [16, 8, 0] {
            XCTAssertLessThanOrEqual(abs(((actual >> shift) & 255) - ((expected >> shift) & 255)), 16,
                                    "Rendered canvas: \(String(actual, radix: 16)); expected \(String(expected, radix: 16))",
                                    file: file, line: line)
        }
    }

    private func click(_ type: NSEvent.EventType, in window: NSWindow,
                       at point: NSPoint = NSPoint(x: 20, y: 20)) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                         clickCount: 1, pressure: 1))
    }

    private func withRunningApplication(_ body: @escaping () throws -> Void) throws {
        try withRunningApplication(untilFinished: { finish in
            try body()
            finish()
        })
    }

    /// The body runs inside a main-queue block, and a run loop spun there never
    /// services the main queue, which is where workspace notifications arrive.
    /// A test waiting for one has to return and call `finish` later.
    private func withRunningApplication(untilFinished body: @escaping (_ finish: @escaping () -> Void) throws -> Void) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var failure: Error?
        var bodyStarted = false
        let stop = {
            app.stop(nil)
            let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!
            app.postEvent(wake, atStart: true)
        }
        let execute = {
            bodyStarted = true
            do { try body(stop) } catch {
                failure = error
                stop()
            }
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
            XCTFail(bodyStarted ? "The popover test did not finish" : "The popover test application did not become active")
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
private final class ProtectedPopoverDelegate: NSObject, NSPopoverDelegate {
    func popoverShouldClose(_ popover: NSPopover) -> Bool { false }
}

@MainActor
private final class ActionCounter: NSObject {
    var count = 0
    @objc func fire() { count += 1 }
}

private final class ClickTarget: NSView {
    var clicks = 0
    override func mouseDown(with event: NSEvent) { clicks += 1 }
    override func rightMouseDown(with event: NSEvent) { clicks += 1 }
    override func otherMouseDown(with event: NSEvent) { clicks += 1 }
}
