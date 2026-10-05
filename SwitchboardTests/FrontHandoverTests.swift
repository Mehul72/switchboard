import AppKit
import XCTest

/// Nothing here changes which app is in front: the request to macOS is a
/// stand-in, and the reports that the front changed are posted by hand.
@MainActor
final class FrontHandoverTests: XCTestCase {
    private func otherApp() throws -> NSRunningApplication {
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        return try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.processIdentifier != ownProcess })
    }

    func testThePanelOpensAtOnceWhenSwitchboardIsNotInFront() throws {
        let stage = HandoverStage(switchboardInFront: false, fullScreenApp: try otherApp())

        stage.openPanel()

        XCTAssertEqual(stage.panelOpenings, 1)
        XCTAssertTrue(stage.appsGivenFront.isEmpty)
    }

    /// A desktop keeps its menu bar showing, so macOS has no reason to move the front.
    func testThePanelOpensAtOnceOnADesktop() {
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: nil)

        stage.openPanel()

        XCTAssertEqual(stage.panelOpenings, 1)
        XCTAssertTrue(stage.appsGivenFront.isEmpty)
    }

    func testOverAFullScreenAppTheFrontGoesBackBeforeThePanelOpens() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp)

        stage.openPanel()
        XCTAssertEqual(stage.appsGivenFront, [fullScreenApp.processIdentifier])
        XCTAssertEqual(stage.panelOpenings, 0, "the panel must not open while Switchboard is still in front")

        stage.reportActivation(of: fullScreenApp)
        XCTAssertEqual(stage.panelOpenings, 0, "AppKit has not resigned yet, and its resigning closes a popover that holds the keyboard")

        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 1)
    }

    func testTheTwoReportsCanArriveInEitherOrder() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp)
        stage.openPanel()

        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 0, "the panel closes itself when the workspace report lands after it opened")

        stage.reportActivation(of: fullScreenApp)
        XCTAssertEqual(stage.panelOpenings, 1)
    }

    func testSwitchboardBecomingActiveIsNotTheFrontGoingBack() throws {
        // A bare test process has no application identity until this exists.
        _ = NSApplication.shared
        XCTAssertEqual(NSRunningApplication.current.processIdentifier, ProcessInfo.processInfo.processIdentifier)
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp)
        stage.openPanel()
        stage.reportAppKitResigned()

        stage.reportActivation(of: .current)
        XCTAssertEqual(stage.panelOpenings, 0)

        stage.reportActivation(of: fullScreenApp)
        XCTAssertEqual(stage.panelOpenings, 1)
    }

    func testWithAppKitAlreadyInactiveTheWorkspaceReportIsEnough() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, activeInAppKit: false, fullScreenApp: fullScreenApp)
        stage.openPanel()

        stage.reportActivation(of: fullScreenApp)

        XCTAssertEqual(stage.panelOpenings, 1)
    }

    func testARefusalFromMacOSOpensThePanelAnyway() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp)
        stage.macOSAllowsTheHandover = false

        stage.openPanel()
        XCTAssertEqual(stage.panelOpenings, 1)

        stage.reportActivation(of: fullScreenApp)
        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 1, "nothing was left waiting for those reports")
    }

    func testThePanelOpensWhenNoReportEverArrives() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp, waitLimitSeconds: 0.05)
        let opened = expectation(description: "the panel opened once the wait ran out")
        stage.onPanelOpening = { opened.fulfill() }

        stage.openPanel()
        XCTAssertEqual(stage.panelOpenings, 0)
        wait(for: [opened], timeout: 5)

        stage.reportActivation(of: fullScreenApp)
        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 1, "late reports must not open it a second time")
    }

    func testASecondRequestWhileWaitingAsksOnceAndOpensOnce() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp)
        var firstRequestOpened = false
        var secondRequestOpened = false

        stage.handover.handBack(on: nil) { firstRequestOpened = true }
        stage.handover.handBack(on: nil) { secondRequestOpened = true }
        XCTAssertEqual(stage.appsGivenFront.count, 1)

        stage.reportActivation(of: fullScreenApp)
        stage.reportAppKitResigned()
        XCTAssertFalse(firstRequestOpened)
        XCTAssertTrue(secondRequestOpened)
    }

    func testAFinishedHandoverStopsListeningAndCanRunAgain() throws {
        let fullScreenApp = try otherApp()
        let stage = HandoverStage(switchboardInFront: true, fullScreenApp: fullScreenApp)
        stage.openPanel()
        stage.reportActivation(of: fullScreenApp)
        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 1)

        stage.reportActivation(of: fullScreenApp)
        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 1)

        stage.openPanel()
        XCTAssertEqual(stage.appsGivenFront.count, 2)
        stage.reportActivation(of: fullScreenApp)
        XCTAssertEqual(stage.panelOpenings, 1, "a report from the first handover must not count towards the second")
        stage.reportAppKitResigned()
        XCTAssertEqual(stage.panelOpenings, 2)
    }
}

/// A handover with macOS replaced: what it is told about the front, what it
/// asks for, and the two reports it waits on.
@MainActor
private final class HandoverStage {
    let handover: FrontHandover
    var macOSAllowsTheHandover = true
    var onPanelOpening: () -> Void = {}
    private(set) var appsGivenFront: [pid_t] = []
    private(set) var panelOpenings = 0
    private let workspace = NotificationCenter()
    private let appKit = NotificationCenter()

    /// The default wait limit is far longer than any test, so only the test
    /// that shortens it ever sees the wait run out.
    init(switchboardInFront: Bool, activeInAppKit: Bool = true, fullScreenApp: NSRunningApplication?,
         waitLimitSeconds: TimeInterval = 600) {
        handover = FrontHandover(workspaceNotifications: workspace, appNotifications: appKit,
                                 waitLimitSeconds: waitLimitSeconds)
        handover.isFrontApp = { switchboardInFront }
        handover.isActiveInAppKit = { activeInAppKit }
        handover.fullScreenApp = { _ in fullScreenApp }
        handover.giveFront = { [unowned self] app in
            self.appsGivenFront.append(app.processIdentifier)
            return self.macOSAllowsTheHandover
        }
    }

    func openPanel() {
        handover.handBack(on: nil) { [unowned self] in
            self.panelOpenings += 1
            self.onPanelOpening()
        }
    }

    func reportActivation(of app: NSRunningApplication) {
        workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                       userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    func reportAppKitResigned() {
        appKit.post(name: NSApplication.didResignActiveNotification, object: nil)
    }
}
