import AppKit
import Carbon
import XCTest

private let testImage: CGImage = {
    let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    return context.makeImage()!
}()

final class WindowSwitchingTests: XCTestCase {
    func testEachWindowOfAnAppStaysSeparateAndDuplicatesAreRemoved() {
        let windows = [window(1, pid: 10), window(2, pid: 10), window(3, pid: 20), window(2, pid: 10)]
        let ordered = SwitcherWindow.ordered(windows, frontmostPID: 10, focusedID: 2,
                                             sameAppOnly: false, frontToBack: [3, 1, 2])
        XCTAssertEqual(ordered.map(\.id), [2, 3, 1])
        let sameApp = SwitcherWindow.ordered(windows, frontmostPID: 10, focusedID: 2,
                                             sameAppOnly: true, frontToBack: [3, 1, 2])
        XCTAssertEqual(sameApp.map(\.id), [2, 1])
        XCTAssertTrue(SwitcherWindow.ordered(windows, frontmostPID: nil, focusedID: nil,
                                             sameAppOnly: true, frontToBack: []).isEmpty)
    }

    func testMinimizedAndHiddenWindowsRemainSelectable() {
        var minimized = window(2, pid: 10)
        minimized.isMinimized = true
        var hidden = window(3, pid: 20)
        hidden.isHidden = true
        let ordered = SwitcherWindow.ordered([hidden, minimized, window(1, pid: 10)], frontmostPID: 10,
                                             focusedID: 1, sameAppOnly: false, frontToBack: [1])
        XCTAssertEqual(ordered.map(\.id), [1, 2, 3])
    }

    func testWindowsOffScreenFollowTheirAppsActivationRecency() {
        // Window 4 is a full-screen app on another Space, used just before app 10.
        let windows = [window(1, pid: 10), window(2, pid: 30), window(3, pid: 10), window(4, pid: 20), window(5, pid: 40)]
        let fromDesktop = SwitcherWindow.ordered(windows, frontmostPID: 10, focusedID: 1, sameAppOnly: false,
                                                 frontToBack: [1, 2, 3], recentPIDs: [10, 20, 30])
        XCTAssertEqual(fromDesktop.map(\.id), [1, 4, 2, 3, 5])
        // Inside the full-screen Space nothing else is on screen.
        let fromFullScreen = SwitcherWindow.ordered(windows, frontmostPID: 20, focusedID: 4, sameAppOnly: false,
                                                    frontToBack: [4], recentPIDs: [10, 20, 30])
        XCTAssertEqual(fromFullScreen.map(\.id), [4, 1, 3, 2, 5])
    }

    func testUsedWindowsOutrankTheFrontmostAppsOtherWindows() {
        // VS Code, then Chrome window 1 in full screen. Chrome window 2 sits on
        // another Space and was used long ago, so VS Code must come next.
        let chromeOne = window(73, pid: 20), chromeTwo = window(4088, pid: 20)
        let code = window(3761, pid: 10), finder = window(3674, pid: 30)
        let ordered = SwitcherWindow.ordered([chromeTwo, finder, code, chromeOne], frontmostPID: 20, focusedID: 73,
                                             sameAppOnly: false, frontToBack: [73], recentPIDs: [20, 10, 30],
                                             recentWindowIDs: [73, 3761])
        XCTAssertEqual(ordered.map(\.id), [73, 3761, 4088, 3674])
        // Windows never seen used keep the stacking and app order after the known ones.
        let desktop = SwitcherWindow.ordered([window(1, pid: 10), window(2, pid: 30), window(3, pid: 10), window(4, pid: 20)],
                                             frontmostPID: 10, focusedID: 1, sameAppOnly: false, frontToBack: [1, 2, 3],
                                             recentPIDs: [10, 20, 30], recentWindowIDs: [3])
        XCTAssertEqual(desktop.map(\.id), [1, 3, 4, 2])
    }

    func testAppsWithoutWindowsFollowTheWindowsByRecency() {
        let preview = SwitcherWindow.windowlessApp(pid: 50, appName: "Preview")
        let finder = SwitcherWindow.windowlessApp(pid: 60, appName: "Finder")
        let notes = SwitcherWindow.windowlessApp(pid: 70, appName: "Notes")
        let ordered = SwitcherWindow.ordered([notes, window(1, pid: 10), finder, preview, window(2, pid: 20)],
                                             frontmostPID: 10, focusedID: 1, sameAppOnly: false,
                                             frontToBack: [1, 2], recentPIDs: [10, 60, 20, 50])
        XCTAssertEqual(ordered.map(\.id), [1, 2, finder.id, preview.id, notes.id])
        XCTAssertTrue(preview.isWindowlessApp)
        XCTAssertNotEqual(preview.id, finder.id)
        XCTAssertEqual(preview.id, SwitcherWindow.windowlessApp(pid: 50, appName: "Preview").id)
        // Window IDs stay below the range app entries use.
        XCTAssertFalse(window(UInt32(Int32.max), pid: 50).isWindowlessApp)
    }

    func testWindowRecencyKeepsTheNewestFirstWithinItsLimit() {
        var recency = WindowRecency()
        for id: UInt32 in [1, 2, 3, 1] { recency.used(id) }
        XCTAssertEqual(recency.ids, [1, 3, 2])
        recency.keep(only: [1, 2])
        XCTAssertEqual(recency.ids, [1, 2])
        for id in UInt32(100)..<UInt32(100 + WindowRecency.limit + 5) { recency.used(id) }
        XCTAssertEqual(recency.ids.count, WindowRecency.limit)
        XCTAssertEqual(recency.ids.first, UInt32(100 + WindowRecency.limit + 4))
    }

    func testRecencyMovesActivatedAppsFirstAndForgetsTerminatedOnes() {
        var recency = ApplicationRecency()
        for pid: Int32 in [10, 20, 30, 10] { recency.activated(pid) }
        XCTAssertEqual(recency.pids, [10, 30, 20])
        recency.terminated(30)
        recency.terminated(99)
        XCTAssertEqual(recency.pids, [10, 20])
    }

    func testQuickReleaseRetainsAllStepsWhileLoading() {
        var session = WindowSwitchingSession(backwards: false)
        session.move(by: 1)
        session.release()
        session.move(by: 1)
        session.load([1, 2, 3], focusedID: 1)
        XCTAssertEqual(session.selectedID, 3)
        XCTAssertTrue(session.shouldCommit)
    }

    func testForwardAndReverseWrapAndSkipTheCurrentWindow() {
        var forward = WindowSwitchingSession(backwards: false)
        forward.load([1, 2, 3], focusedID: 1)
        XCTAssertEqual(forward.selectedID, 2)
        forward.move(by: 2)
        XCTAssertEqual(forward.selectedID, 1)
        forward.move(by: -1)
        XCTAssertEqual(forward.selectedID, 3)
        var reverse = WindowSwitchingSession(backwards: true)
        reverse.load([1, 2, 3], focusedID: 1)
        XCTAssertEqual(reverse.selectedID, 3)
    }

    func testNoFocusedWindowStartsAtFirstOrLastEntry() {
        var forward = WindowSwitchingSession(backwards: false)
        forward.load([1, 2, 3], focusedID: nil)
        XCTAssertEqual(forward.selectedID, 1)
        var reverse = WindowSwitchingSession(backwards: true)
        reverse.load([1, 2, 3], focusedID: 99)
        XCTAssertEqual(reverse.selectedID, 3)
    }

    func testEmptyAndSingleWindowSessionsAreSafe() {
        var empty = WindowSwitchingSession(backwards: true)
        empty.load([], focusedID: nil)
        empty.move(by: -100)
        empty.release()
        XCTAssertNil(empty.selectedID)
        var single = WindowSwitchingSession(backwards: true)
        single.load([7, 7], focusedID: 7)
        single.move(by: 12)
        XCTAssertEqual(single.ids, [7])
        XCTAssertEqual(single.selectedID, 7)
    }

    func testMouseSelectionCannotChangeAfterCommitAndReloadIsIgnored() {
        var session = WindowSwitchingSession(backwards: false)
        session.load([1, 2, 3], focusedID: 1)
        session.select(99)
        XCTAssertEqual(session.selectedID, 2)
        session.select(3)
        session.load([4, 5], focusedID: 4)
        session.release()
        session.select(1)
        XCTAssertEqual(session.selectedID, 3)
    }

    func testRemovingCardsKeepsTheSelectionOnTheFollowingCard() {
        var session = WindowSwitchingSession(backwards: false)
        session.load([1, 2, 3, 4], focusedID: 1)
        session.remove([2, 3])
        XCTAssertEqual(session.ids, [1, 4])
        XCTAssertEqual(session.selectedID, 4)
        session.move(by: 1)
        session.remove([1])
        XCTAssertEqual(session.selectedID, 4)
        session.remove([4])
        XCTAssertTrue(session.ids.isEmpty)
        XCTAssertNil(session.selectedID)
        var wrapping = WindowSwitchingSession(backwards: true)
        wrapping.load([1, 2, 3], focusedID: 1)
        wrapping.remove([3])
        XCTAssertEqual(wrapping.selectedID, 1)
    }

    func testHiddenWindowMemoryLooksEachWindowUpOnce() {
        var memory = HiddenWindowMemory<String>()
        memory.remember("element 73", for: 73)
        XCTAssertEqual(memory.unsearched([73, 4088, 4090]), [4088, 4090])
        memory.markSearched([4088, 4090])
        XCTAssertTrue(memory.unsearched([73, 4088, 4090]).isEmpty)
        // Seen later on its own Space, a searched window becomes known.
        memory.remember("element 4088", for: 4088)
        XCTAssertEqual(memory.element(for: 4088), "element 4088")
        memory.forget(73)
        XCTAssertEqual(memory.unsearched([73]), [73])
        memory.keep(only: [4088])
        XCTAssertNil(memory.element(for: 73))
        XCTAssertEqual(memory.unsearched([4090]), [4090])
        memory.removeAll()
        XCTAssertNil(memory.element(for: 4088))
    }

    func testElementScanStopsOnlyAfterAQuietStretchPastTheNewestElement() {
        let quiet = ElementScan.quietIDsBeforeStop
        XCTAssertFalse(ElementScan.isPastNewestElement(quiet, newestLiveID: nil))
        XCTAssertTrue(ElementScan.isPastNewestElement(quiet + 1, newestLiveID: nil))
        // Chrome's second full-screen window was element 1561, well past 1000.
        XCTAssertFalse(ElementScan.isPastNewestElement(1561, newestLiveID: 1370))
        XCTAssertTrue(ElementScan.isPastNewestElement(1587 + quiet + 1, newestLiveID: 1587))
    }

    private func window(_ id: UInt32, pid: Int32) -> SwitcherWindow {
        SwitcherWindow(id: id, pid: pid, appName: "App \(pid)", title: "Window \(id)")
    }
}

@MainActor
final class WindowSwitcherControllerTests: XCTestCase {
    func testCommandReleasedBeforeShortcutDeliveryStillSelectsTheNextWindow() {
        let (controller, inventory, input) = fixture()
        input.modifiersAreHeld = false
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        XCTAssertFalse(input.active)
        inventory.complete(0, ids: [1, 2, 3])
        XCTAssertEqual(inventory.focused, [2])
        XCTAssertFalse(controller.isShowing)
    }

    func testReleaseBeforeEnumerationFocusesTheSelectedWindowOnce() {
        let (controller, inventory, input) = fixture()
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(optionKey))
        input.onCommand?(.move(1))
        input.onCommand?(.commit)
        XCTAssertFalse(input.active)
        inventory.complete(0, ids: [1, 2, 3])
        XCTAssertEqual(inventory.focused, [3])
        XCTAssertFalse(controller.isShowing)
        controller.commit()
        XCTAssertEqual(inventory.focused, [3])
    }

    func testCancelledEnumerationCannotReopenOrCommit() {
        let (controller, inventory, input) = fixture()
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(optionKey))
        input.onCommand?(.cancel)
        inventory.complete(0, ids: [1, 2])
        XCTAssertTrue(inventory.focused.isEmpty)
        XCTAssertTrue(controller.windows.isEmpty)
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(input.active)
    }

    func testOldResponseCannotReplaceANewerSession() {
        let (controller, inventory, _) = fixture()
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(optionKey))
        controller.cancel()
        controller.advance(sameAppOnly: true, backwards: true, modifiers: UInt32(optionKey | shiftKey))
        inventory.complete(1, ids: [4, 5, 6])
        inventory.complete(0, ids: [1, 2])
        XCTAssertEqual(controller.windows.map(\.id), [4, 5, 6])
        XCTAssertEqual(controller.selectedID, 6)
        XCTAssertTrue(controller.sameAppOnly)
        controller.choose(5)
        XCTAssertEqual(inventory.focused, [5])
    }

    func testMissingPermissionAndFailedInputHookLeaveKeyboardAlone() {
        let inventory = TestSwitcherInventory()
        let input = TestSwitcherInput()
        let controller = WindowSwitcher(inventory: inventory, input: input, hasAccessibility: { false }, canCapture: { false })
        var errors: [String] = []
        controller.onError = { errors.append($0) }
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(optionKey))
        XCTAssertFalse(input.active)
        XCTAssertTrue(inventory.requests.isEmpty)
        XCTAssertEqual(errors.count, 1)
        let permitted = WindowSwitcher(inventory: inventory, input: input, hasAccessibility: { true }, canCapture: { false })
        permitted.onError = { errors.append($0) }
        input.canStart = false
        permitted.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(optionKey))
        XCTAssertFalse(permitted.isShowing)
        XCTAssertTrue(inventory.requests.isEmpty)
        XCTAssertEqual(errors.count, 2)
    }

    func testEmptyListReportsFailureAndTearsDownInput() {
        let (controller, inventory, input) = fixture()
        var error: String?
        controller.onError = { error = $0 }
        controller.advance(sameAppOnly: true, backwards: false, modifiers: UInt32(optionKey))
        inventory.complete(0, ids: [])
        XCTAssertNotNil(error)
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(input.active)
        XCTAssertTrue(inventory.focused.isEmpty)
    }

    func testKeysAndModifiersRespectReverseAndAssistiveTechnology() {
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_Tab), flags: [.maskAlternate, .maskShift]), .move(-1))
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_Escape), flags: .maskAlternate), .cancel)
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_Return), flags: []), .commit)
        XCTAssertNil(SwitcherInput.command(keyCode: Int64(kVK_RightArrow), flags: [.maskAlternate, .maskControl]))
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_Escape), flags: .maskControl,
                                             heldModifiers: .maskControl), .cancel)
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_Tab), flags: [.maskCommand, .maskShift],
                                             heldModifiers: .maskCommand), .move(-1))
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_Escape), flags: .maskCommand,
                                             heldModifiers: .maskCommand), .cancel)
        XCTAssertEqual(WindowSwitcher.heldFlags(UInt32(optionKey | shiftKey)), .maskAlternate)
        XCTAssertEqual(WindowSwitcher.heldFlags(UInt32(cmdKey | controlKey)), [.maskCommand, .maskControl])
    }

    func testQuitRemovesTheAppsCardsOnceItTerminates() {
        var requests: [pid_t] = []
        let (controller, inventory, input) = fixture(quit: { requests.append($0); return true })
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(0, windows: [(1, 100), (2, 200), (3, 200), (4, 300)])
        XCTAssertEqual(controller.selectedID, 2)
        input.onCommand?(.quit)
        input.onCommand?(.quit)
        XCTAssertEqual(requests, [200])
        controller.applicationTerminated(200)
        XCTAssertEqual(controller.windows.map(\.id), [1, 4])
        XCTAssertEqual(controller.selectedID, 4)
        XCTAssertTrue(controller.isShowing)
        input.onCommand?(.commit)
        XCTAssertEqual(inventory.focused, [4])
    }

    func testReleasingBeforeTheQuitAppTerminatesDoesNotFocusIt() {
        let (controller, inventory, input) = fixture(quit: { _ in true })
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(0, windows: [(1, 100), (2, 200)])
        input.onCommand?(.quit)
        input.onCommand?(.commit)
        XCTAssertTrue(inventory.focused.isEmpty)
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(input.active)
    }

    func testQuittingTheOnlyAppClosesAndARefusedQuitKeepsItsCards() {
        let (refusing, refusedInventory, refusedInput) = fixture(quit: { _ in false })
        refusing.advance(sameAppOnly: true, backwards: false, modifiers: UInt32(optionKey))
        refusedInventory.complete(0, windows: [(1, 100), (2, 100)])
        refusedInput.onCommand?(.quit)
        refusedInput.onCommand?(.commit)
        XCTAssertEqual(refusedInventory.focused, [2])

        let (controller, inventory, input) = fixture(quit: { _ in true })
        controller.advance(sameAppOnly: true, backwards: false, modifiers: UInt32(optionKey))
        input.onCommand?(.quit)
        inventory.complete(0, windows: [(1, 100), (2, 100)])
        input.onCommand?(.quit)
        controller.applicationTerminated(100)
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(input.active)
        XCTAssertTrue(inventory.focused.isEmpty)
    }

    func testQuitFollowsTheTypedLetterAndIgnoresKeyRepeat() {
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_ANSI_Q), characters: "q", flags: .maskCommand,
                                             heldModifiers: .maskCommand), .quit)
        // On AZERTY the Q character is on the key QWERTY calls A.
        XCTAssertEqual(SwitcherInput.command(keyCode: Int64(kVK_ANSI_A), characters: "q", flags: .maskAlternate), .quit)
        XCTAssertNil(SwitcherInput.command(keyCode: Int64(kVK_ANSI_Q), characters: "a", flags: .maskAlternate))
        XCTAssertNil(SwitcherInput.command(keyCode: Int64(kVK_ANSI_Q), characters: "q", flags: .maskControl,
                                           heldModifiers: .maskCommand))

        let input = SwitcherInput()
        var commands: [SwitcherInput.Command] = []
        input.onCommand = { commands.append($0) }
        let press = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: true)!
        XCTAssertNil(input.handle(.keyDown, press))
        press.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertNil(input.handle(.keyDown, press))
        XCTAssertEqual(commands, [.quit])
    }

    func testHoverSelectsOnlyAfterThePointerMoves() {
        var pointer = CGPoint(x: 10, y: 10)
        let (controller, inventory, _) = fixture(pointer: { pointer })
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(0, ids: [1, 2, 3])
        controller.hover(3)
        XCTAssertEqual(controller.selectedID, 2)
        pointer.x += 5
        controller.hover(3)
        XCTAssertEqual(controller.selectedID, 3)
        controller.hover(1)
        XCTAssertEqual(controller.selectedID, 3)
        // Moving within the selected card must not republish or re-announce it.
        var changes = 0
        let subscription = controller.objectWillChange.sink { changes += 1 }
        pointer.x += 5
        controller.hover(3)
        XCTAssertEqual(changes, 0)
        subscription.cancel()
    }

    func testAppsWithoutWindowsCanBeReachedChosenAndQuitButGetNoPreview() {
        var started: [(id: UInt32, finish: (CGImage?) -> Void)] = []
        var quits: [pid_t] = []
        let previews = SwitcherPreviews(capture: { started.append(($0, $1)) })
        let (controller, inventory, input) = fixture(quit: { quits.append($0); return true }, previews: previews,
                                                     canCapture: { true })
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(0, windows: [(1, 100), (2, 200)], windowlessApps: [300, 400])
        let preview = SwitcherWindow.windowlessApp(pid: 300, appName: "App 300").id
        XCTAssertEqual(controller.windows.map(\.id).suffix(2), [preview, SwitcherWindow.windowlessApp(pid: 400, appName: "").id])
        input.onCommand?(.move(1))
        XCTAssertEqual(controller.selectedID, preview)
        controller.previewNeeded(preview)
        XCTAssertEqual(started.map(\.id), [2])
        input.onCommand?(.quit)
        XCTAssertEqual(quits, [300])
        controller.applicationTerminated(300)
        XCTAssertFalse(controller.windows.contains { $0.pid == 300 })
        input.onCommand?(.commit)
        XCTAssertEqual(inventory.focused, [SwitcherWindow.windowlessApp(pid: 400, appName: "").id])
    }

    func testDisablingClosesTheSwitcherAndStopsRememberingWindows() {
        var started: [(id: UInt32, finish: (CGImage?) -> Void)] = []
        let previews = SwitcherPreviews(capture: { started.append(($0, $1)) })
        let (controller, inventory, input) = fixture(previews: previews, canCapture: { true })
        controller.setEnabled(true)
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(0, ids: [1, 2])
        started.removeFirst().finish(testImage)
        controller.setEnabled(false)
        XCTAssertEqual(inventory.remembersWindows, [true, false])
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(input.active)
        XCTAssertTrue(previews.thumbnails(for: [2]).isEmpty)
    }

    func testCardsShowKnownPreviewsAtOnceAndQuickSwitchesCaptureNothing() {
        var started: [(id: UInt32, finish: (CGImage?) -> Void)] = []
        let previews = SwitcherPreviews(capture: { started.append(($0, $1)) })
        let (controller, inventory, input) = fixture(previews: previews, canCapture: { true })
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(0, ids: [1, 2, 3])
        XCTAssertEqual(started.map(\.id), [2])
        controller.previewNeeded(1)
        controller.previewNeeded(3)
        started.removeFirst().finish(testImage)
        XCTAssertNotNil(controller.images[2])
        XCTAssertEqual(started.map(\.id), [1])
        controller.cancel()
        started.removeFirst().finish(testImage)
        XCTAssertTrue(started.isEmpty)

        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(1, ids: [1, 2, 3])
        XCTAssertEqual(Set(controller.images.keys), [1, 2])
        XCTAssertTrue(started.isEmpty)
        controller.cancel()

        input.modifiersAreHeld = false
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        inventory.complete(2, ids: [4, 5])
        controller.previewNeeded(4)
        XCTAssertTrue(started.isEmpty)
    }

    func testSleepTurningOffAndLosingPermissionForgetPreviews() {
        var started: [(id: UInt32, finish: (CGImage?) -> Void)] = []
        var permitted = true
        let previews = SwitcherPreviews(capture: { started.append(($0, $1)) })
        let (controller, inventory, _) = fixture(previews: previews, canCapture: { permitted })
        func captureSelected(_ request: Int) {
            controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
            inventory.complete(request, ids: [1, 2])
            started.removeFirst().finish(testImage)
            controller.cancel()
        }
        captureSelected(0)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertTrue(previews.thumbnails(for: [2]).isEmpty)
        captureSelected(1)
        controller.discardPreviews()
        XCTAssertTrue(previews.thumbnails(for: [2]).isEmpty)
        captureSelected(2)
        permitted = false
        controller.advance(sameAppOnly: false, backwards: false, modifiers: UInt32(cmdKey))
        XCTAssertTrue(previews.thumbnails(for: [2]).isEmpty)
        inventory.complete(3, ids: [1, 2])
        controller.previewNeeded(1)
        XCTAssertTrue(started.isEmpty)
    }

    private func fixture(quit: @escaping (pid_t) -> Bool = { _ in false },
                         pointer: @escaping () -> CGPoint = { .zero },
                         previews: SwitcherPreviews? = nil,
                         canCapture: @escaping () -> Bool = { false }) -> (WindowSwitcher, TestSwitcherInventory, TestSwitcherInput) {
        _ = NSApplication.shared
        let inventory = TestSwitcherInventory()
        let input = TestSwitcherInput()
        let controller = WindowSwitcher(inventory: inventory, input: input, hasAccessibility: { true }, canCapture: canCapture,
                                        requestQuit: quit, pointerLocation: pointer, previews: previews)
        return (controller, inventory, input)
    }
}

private final class TestSwitcherInventory: SwitcherWindowProviding {
    var requests: [(Result<SwitcherWindowSnapshot, Error>) -> Void] = []
    var focused: [UInt32] = []
    var remembersWindows: [Bool] = []

    func setRemembersWindows(_ enabled: Bool) { remembersWindows.append(enabled) }

    func snapshot(frontmostPID: pid_t?, sameAppOnly: Bool, completion: @escaping (Result<SwitcherWindowSnapshot, Error>) -> Void) {
        requests.append(completion)
    }

    func focus(_ target: SwitcherWindowTarget, completion: @escaping (Result<Void, Error>) -> Void) {
        focused.append(target.info.id)
        completion(.success(()))
    }

    func complete(_ request: Int, ids: [UInt32]) {
        complete(request, windows: ids.map { ($0, 123) })
    }

    func complete(_ request: Int, windows: [(id: UInt32, pid: pid_t)], windowlessApps: [pid_t] = []) {
        let targets = windows.map { window in
            SwitcherWindowTarget(info: SwitcherWindow(id: window.id, pid: window.pid, appName: "App \(window.pid)",
                                                      title: "Window \(window.id)"),
                                 element: AXUIElementCreateApplication(window.pid))
        } + windowlessApps.map { pid in
            SwitcherWindowTarget(info: .windowlessApp(pid: pid, appName: "App \(pid)"), element: AXUIElementCreateApplication(pid))
        }
        requests[request](.success(SwitcherWindowSnapshot(windows: targets, focusedID: windows.first?.id)))
    }
}

@MainActor
private final class TestSwitcherInput: SwitcherInputMonitoring {
    var onCommand: ((SwitcherInput.Command) -> Void)?
    var shouldPassShortcut: ((GlobalShortcut) -> Bool)?
    var modifiersAreHeld = true
    var canStart = true
    var active = false

    func start(modifiers: CGEventFlags) -> Bool { active = canStart; return canStart }
    func stop() { active = false }
}

@MainActor
final class SwitcherPreviewsTests: XCTestCase {
    private var started: [(id: UInt32, finish: (CGImage?) -> Void)] = []
    private var now: TimeInterval = 100
    private var delivered: [UInt32] = []

    private func makePreviews(limit: Int = 48) -> SwitcherPreviews {
        let previews = SwitcherPreviews(capture: { [unowned self] id, finish in started.append((id, finish)) },
                                        clock: { [unowned self] in now }, limit: limit)
        previews.onPreview = { [unowned self] id, _ in delivered.append(id) }
        return previews
    }

    private func finishNext(with image: CGImage? = testImage) {
        started.removeFirst().finish(image)
    }

    func testSelectedCardJumpsTheQueueAndCapturesRunOneAtATime() {
        let previews = makePreviews()
        previews.request(1)
        previews.request(2)
        previews.request(2)
        previews.request(3, first: true)
        XCTAssertEqual(started.map(\.id), [1])
        finishNext()
        finishNext()
        finishNext()
        XCTAssertTrue(started.isEmpty)
        XCTAssertEqual(delivered, [1, 3, 2])
        XCTAssertEqual(Set(previews.thumbnails(for: [1, 2, 3, 4]).keys), [1, 2, 3])
    }

    func testFreshThumbnailsAreReusedAndOldOnesRefreshed() {
        let previews = makePreviews()
        previews.request(1)
        finishNext()
        now += 1
        previews.request(1)
        XCTAssertTrue(started.isEmpty)
        now += SwitcherPreviews.freshSeconds
        previews.request(1)
        XCTAssertEqual(started.map(\.id), [1])
    }

    func testFailedCaptureKeepsTheIconAndMovesOn() {
        let previews = makePreviews()
        previews.request(1)
        previews.request(2)
        finishNext(with: nil)
        XCTAssertEqual(started.map(\.id), [2])
        XCTAssertTrue(previews.thumbnails(for: [1]).isEmpty)
        XCTAssertTrue(delivered.isEmpty)
    }

    func testClosingDropsQueuedWorkButKeepsTheCaptureInFlight() {
        let previews = makePreviews()
        previews.request(1)
        previews.request(2)
        previews.cancelRequests()
        finishNext()
        XCTAssertTrue(started.isEmpty)
        XCTAssertEqual(Set(previews.thumbnails(for: [1, 2]).keys), [1])
    }

    func testPruneForgetsClosedWindowsAndDiscardIgnoresLateResults() {
        let previews = makePreviews()
        previews.request(1)
        finishNext()
        previews.request(2)
        finishNext()
        previews.prune(keeping: [2])
        XCTAssertEqual(Set(previews.thumbnails(for: [1, 2]).keys), [2])
        now += SwitcherPreviews.freshSeconds
        previews.request(2)
        previews.discardAll()
        finishNext()
        XCTAssertTrue(previews.thumbnails(for: [2]).isEmpty)
        XCTAssertEqual(delivered, [1, 2])
        previews.request(3)
        XCTAssertEqual(started.map(\.id), [3])
    }

    func testOldestThumbnailIsEvictedPastTheLimit() {
        let previews = makePreviews(limit: 2)
        for id: UInt32 in [1, 2, 3] {
            now += 1
            previews.request(id)
            finishNext()
        }
        XCTAssertEqual(Set(previews.thumbnails(for: [1, 2, 3]).keys), [2, 3])
    }
}
