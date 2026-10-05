import AppKit
import Combine
import XCTest

/// Drives the store against a throwaway preference domain, in-memory defaults
/// and a private pasteboard.
///
/// Never switch on mouse scrolling, red-button quit, snapping or switching
/// here, never call `applyPendingRestarts`, and never capture screen text
/// with the live source. A shell with Accessibility access would install real
/// input hooks, restart the real Finder, or put a crosshair on the screen.
@MainActor
final class TweakStoreTests: XCTestCase {
    private var domain = ""
    private var defaults: UserDefaults!
    private var pasteboard: NSPasteboard!

    private var restartsFinder: Tweak {
        Tweak(id: "test.flag", title: "Show the flag", category: .files, symbol: "eye",
              domain: domain, key: "flag", onValue: .bool(true), offValue: .bool(false), restart: .finder)
    }

    private var deletesWhenOff: Tweak {
        Tweak(id: "test.plain", title: "Plain setting", subtitle: "Applies at once", category: .dock,
              symbol: "scroll", domain: domain, key: "plain", onValue: .string("on"),
              successMessage: "Saved plainly.")
    }

    private var folder: Tweak {
        Tweak(id: "test.folder", title: "Save into", category: .capture, symbol: "folder",
              domain: domain, key: "folder", onValue: .string("/tmp"), control: .folder)
    }

    private var makePlain: Tweak {
        Tweak(id: "test.make-plain", title: "Strip formatting", category: .everyday, symbol: "doc",
              control: .button("Make Plain"), behavior: .plainTextClipboard)
    }

    override func setUp() async throws {
        try await super.setUp()
        domain = ScratchPreferenceDomain.make("store")
        defaults = InMemoryDefaults()
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() async throws {
        for key in ["flag", "plain", "folder"] {
            PreferenceStore.write(nil, domain: domain, key: key)
        }
        pasteboard.releaseGlobally()
        pasteboard = nil
        defaults = nil
        try await super.tearDown()
    }

    private func makeStore() -> TweakStore {
        TweakStore(catalog: [restartsFinder, deletesWhenOff, folder, makePlain],
                   defaults: defaults, pasteboard: pasteboard, screenText: FakeScreen().source)
    }

    private func stored(_ key: String) -> Any? {
        PreferenceStore.storedValue(domain: domain, key: key)
    }

    func testTurningASettingOnWritesItAndAsksForItsRestart() {
        let store = makeStore()
        XCTAssertFalse(store.isOn(restartsFinder))

        store.setOn(restartsFinder, true)

        XCTAssertEqual((stored("flag") as? NSNumber)?.boolValue, true)
        XCTAssertTrue(store.isOn(restartsFinder))
        XCTAssertEqual(store.pendingRestarts, [.finder])
        XCTAssertEqual(store.notice?.kind, .information)
        XCTAssertEqual(store.notice?.message, "Saved. Restart Finder to apply it.")
    }

    func testASettingWithNoRestartReportsItsOwnMessage() {
        let store = makeStore()

        store.setOn(deletesWhenOff, true)

        XCTAssertEqual(stored("plain") as? String, "on")
        XCTAssertTrue(store.pendingRestarts.isEmpty)
        XCTAssertEqual(store.notice?.kind, .success)
        XCTAssertEqual(store.notice?.message, "Saved plainly.")
    }

    func testTurningOffASettingWithNoOffValueDeletesTheKey() {
        let store = makeStore()
        store.setOn(deletesWhenOff, true)

        store.setOn(deletesWhenOff, false)

        XCTAssertNil(stored("plain"))
        XCTAssertFalse(store.isOn(deletesWhenOff))
        XCTAssertEqual(store.notice?.kind, .success)
    }

    func testASettingWrittenOutsideTheAppShowsAfterRefresh() {
        let store = makeStore()
        PreferenceStore.write(.string("YES"), domain: domain, key: "flag")

        store.refresh()

        XCTAssertTrue(store.isOn(restartsFinder), "text written by `defaults write` still reads as on")
    }

    func testRestoreOriginalSettingsPutsBackWhatWasThere() {
        PreferenceStore.write(.bool(false), domain: domain, key: "flag")
        let store = makeStore()
        XCTAssertFalse(store.canRestoreOriginalSettings)
        store.setOn(restartsFinder, true)
        store.setOn(deletesWhenOff, true)
        XCTAssertTrue(store.canRestoreOriginalSettings)

        store.restoreDefaults()

        XCTAssertEqual((stored("flag") as? NSNumber)?.boolValue, false)
        XCTAssertNil(stored("plain"))
        XCTAssertTrue(store.pendingRestarts.contains(.finder), "Finder still has to reread the restored value")
        XCTAssertEqual(store.notice?.message, "Original settings restored.")
        XCTAssertFalse(store.canRestoreOriginalSettings)
    }

    func testOriginalValuesAreRememberedAcrossARelaunch() {
        PreferenceStore.write(.bool(false), domain: domain, key: "flag")
        makeStore().setOn(restartsFinder, true)

        let relaunched = makeStore()
        XCTAssertTrue(relaunched.canRestoreOriginalSettings)
        relaunched.restoreDefaults()

        XCTAssertEqual((stored("flag") as? NSNumber)?.boolValue, false)
    }

    /// With Accessibility revoked the feature is idle but its switch is still
    /// stored on, and Restore Original Settings is what clears it.
    func testRestoreIsOfferedForAStoredWindowSwitchEvenWhileIdle() {
        defaults.set(true, forKey: "WindowSnappingEnabled")
        let store = makeStore()

        XCTAssertTrue(store.canRestoreOriginalSettings)
        store.restoreDefaults()

        XCTAssertFalse(defaults.bool(forKey: "WindowSnappingEnabled"))
        XCTAssertFalse(store.canRestoreOriginalSettings)
    }

    func testAFolderThatCannotBeWrittenIsRefusedAndNothingIsSaved() {
        let store = makeStore()

        store.select(.string("/nonexistent-\(UUID().uuidString)"), for: folder)

        XCTAssertNil(stored("folder"))
        XCTAssertEqual(store.notice?.kind, .error)
        XCTAssertFalse(store.canRestoreOriginalSettings, "a refused change must not leave an undo record")
    }

    func testAWritableFolderIsSaved() {
        let store = makeStore()
        let chosen = FileManager.default.temporaryDirectory.path

        store.select(.string(chosen), for: folder)

        XCTAssertEqual(stored("folder") as? String, chosen)
        XCTAssertEqual(store.stringValue(folder), chosen)
    }

    func testSearchMatchesTitleSubtitleAndCategoryAcrossCategories() {
        let store = makeStore()
        store.category = .files
        XCTAssertEqual(store.visible.map(\.id), ["test.flag"])
        XCTAssertEqual(store.visibleCategories, [.files])

        store.search = "applies at once"
        XCTAssertEqual(store.visible.map(\.id), ["test.plain"])
        XCTAssertEqual(store.visibleCategories, [.dock])

        store.search = "capture"
        XCTAssertEqual(store.visible.map(\.id), ["test.folder"])

        store.search = "no such setting"
        XCTAssertTrue(store.visible.isEmpty)
        XCTAssertTrue(store.visibleCategories.isEmpty)
    }

    func testMakePlainStripsFormattingOnTheStoresOwnPasteboard() {
        let store = makeStore()
        let styled = NSPasteboardItem()
        styled.setString("styled", forType: .string)
        styled.setData(Data("{\\rtf1 styled}".utf8), forType: .rtf)
        pasteboard.clearContents()
        pasteboard.writeObjects([styled])

        store.perform(makePlain)

        XCTAssertEqual(pasteboard.string(forType: .string), "styled")
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertEqual(store.notice?.message, "Clipboard formatting removed.")
    }

    func testEveryOptionalBehaviourStartsOn() {
        let store = makeStore()

        for behavior in OptionalBehavior.allCases {
            XCTAssertTrue(store.isEnabled(behavior), behavior.rawValue)
        }
        XCTAssertTrue(store.isRecordingClipboard)
    }

    func testSwitchingClipboardHistoryOffForgetsItsClipsAndStaysOffAfterRelaunch() {
        let store = makeStore()
        let recorded = expectation(description: "the clipboard poll recorded the copy")
        recorded.assertForOverFulfill = false
        let subscription = store.$clips.sink { clips in if !clips.isEmpty { recorded.fulfill() } }
        defer { subscription.cancel() }
        pasteboard.clearContents()
        pasteboard.setString("kept until history is switched off", forType: .string)
        wait(for: [recorded], timeout: 5)

        store.setEnabled(.clipboardHistory, false)

        XCTAssertTrue(store.clips.isEmpty, "switching it off is a request to stop holding copies")
        XCTAssertFalse(store.isRecordingClipboard)
        XCTAssertEqual(store.notice?.message, "Clipboard history is off, and its clips are forgotten.")
        XCTAssertEqual(defaults.object(forKey: "ClipboardHistoryEnabled") as? Bool, false)

        let relaunched = makeStore()
        XCTAssertFalse(relaunched.isEnabled(.clipboardHistory))
        XCTAssertFalse(relaunched.isRecordingClipboard)

        relaunched.setEnabled(.clipboardHistory, true)
        XCTAssertTrue(relaunched.isRecordingClipboard)
        XCTAssertTrue(makeStore().isEnabled(.clipboardHistory))
    }

    func testAChangedSwitchIsReportedOnceAndAnUnchangedOneNotAtAll() {
        let store = makeStore()
        var changes: [String] = []
        store.onBehaviorChange = { behavior, enabled in changes.append("\(behavior.rawValue)=\(enabled)") }

        store.setEnabled(.shelfDragTrigger, true)
        XCTAssertTrue(changes.isEmpty, "it was already on")
        store.setEnabled(.shelfDragTrigger, false)
        store.setEnabled(.shelfDragTrigger, false)
        store.setEnabled(.finderEject, false)
        store.setEnabled(.finderEject, true)

        XCTAssertEqual(changes, ["ShelfOpensDuringDrags=false", "FinderCommandDeleteEjects=false",
                                 "FinderCommandDeleteEjects=true"])
        XCTAssertFalse(store.isEnabled(.shelfDragTrigger))
        XCTAssertTrue(store.isEnabled(.finderEject))
    }

    func testRedButtonExclusionsArePublishedAndSurviveARelaunch() {
        let store = makeStore()
        XCTAssertTrue(store.quitOnCloseExclusions.isEmpty)

        store.setQuitOnCloseExcluded(true, bundleID: "com.apple.Music")
        store.setQuitOnCloseExcluded(true, bundleID: "com.example.downloader")
        store.setQuitOnCloseExcluded(false, bundleID: "com.example.downloader")

        XCTAssertEqual(store.quitOnCloseExclusions, ["com.apple.Music"])
        XCTAssertEqual(makeStore().quitOnCloseExclusions, ["com.apple.Music"])
    }

    func testMakePlainWithNothingCopiedSaysSoAndLeavesTheClipboardAlone() {
        let store = makeStore()
        pasteboard.clearContents()

        store.perform(makePlain)

        XCTAssertEqual(store.notice?.kind, .information)
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}

/// Stands in for the system's selection UI and for Vision. Each call is kept
/// so a test decides when, and how, it answers.
@MainActor
final class FakeScreen {
    private(set) var selections: [(Result<Data, Error>) -> Void] = []
    private(set) var reads: [(Result<String, Error>) -> Void] = []
    private(set) var preparations: [(Bool) -> Void] = []
    var onPrepare: () -> Void = {}

    var source: ScreenTextSource {
        ScreenTextSource(selectRegion: { self.selections.append($0) },
                         recognise: { _, answer in self.reads.append(answer) },
                         prepare: { answer in
                             self.preparations.append(answer)
                             self.onPrepare()
                         },
                         prepareDelaySeconds: 0)
    }
}

/// Reading the text can take half a minute the first time. These pin down
/// that nothing waits for it.
@MainActor
final class ScreenTextCaptureTests: XCTestCase {
    private let copyText = Tweak(id: "test.copy-text", title: "Copy text from the screen",
                                 category: .everyday, symbol: "text.viewfinder",
                                 control: .button("Select Area"), behavior: .regionOCR)
    private let picture = Data([1, 2, 3])
    private var defaults: UserDefaults!
    private var pasteboard: NSPasteboard!
    private var screen: FakeScreen!
    private var selectionsBegun = 0
    private var selectionsEnded = 0

    override func setUp() async throws {
        try await super.setUp()
        defaults = InMemoryDefaults()
        pasteboard = NSPasteboard.withUniqueName()
        screen = FakeScreen()
        selectionsBegun = 0
        selectionsEnded = 0
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        pasteboard = nil
        screen = nil
        defaults = nil
        try await super.tearDown()
    }

    private func makeStore() -> TweakStore {
        let store = TweakStore(catalog: [copyText], defaults: defaults, pasteboard: pasteboard,
                               screenText: screen.source)
        store.onScreenSelectionBegan = { [unowned self] in self.selectionsBegun += 1 }
        store.onScreenSelectionEnded = { [unowned self] in self.selectionsEnded += 1 }
        return store
    }

    func testOnlyTheSelectionHoldsTheAppAndTheReadDoesNot() {
        let store = makeStore()

        store.perform(copyText)
        XCTAssertTrue(store.isSelectingScreenRegion)
        XCTAssertEqual(selectionsBegun, 1)
        XCTAssertEqual(selectionsEnded, 0)

        screen.selections[0](.success(picture))
        XCTAssertFalse(store.isSelectingScreenRegion, "the crosshair has gone, so the panel and shortcuts are free again")
        XCTAssertTrue(store.isReadingScreenText)
        XCTAssertEqual(selectionsEnded, 1, "the panel comes back now, not when the read finishes")
        XCTAssertEqual(store.notice?.kind, .information)
        XCTAssertEqual(store.notice?.message.hasPrefix("Reading the text"), true)

        screen.reads[0](.success("first line\nsecond line"))
        XCTAssertFalse(store.isReadingScreenText)
        XCTAssertEqual(pasteboard.string(forType: .string), "first line\nsecond line")
        XCTAssertEqual(store.notice?.message, "Copied 2 lines of text.")
        XCTAssertEqual(store.clips.first?.note, "Captured from the screen")
        XCTAssertEqual(store.category, .clipboard)
        XCTAssertEqual(selectionsEnded, 1, "the panel is not brought back a second time")
    }

    func testACancelledSelectionEndsTheCaptureWithNothingToRead() {
        let store = makeStore()
        store.perform(copyText)

        screen.selections[0](.failure(TextCapture.CaptureError.cancelled))

        XCTAssertFalse(store.isSelectingScreenRegion)
        XCTAssertFalse(store.isReadingScreenText)
        XCTAssertTrue(screen.reads.isEmpty)
        XCTAssertEqual(selectionsEnded, 1)
        XCTAssertEqual(store.notice?.kind, .information)
        XCTAssertEqual(store.notice?.message, "Selection cancelled.")
        XCTAssertTrue(store.canPerform(copyText))
    }

    func testAMissingPermissionIsReportedWithAWayToTheSetting() {
        let store = makeStore()
        store.perform(copyText)

        screen.selections[0](.failure(TextCapture.CaptureError.permissionDenied))

        XCTAssertEqual(store.notice?.kind, .error)
        XCTAssertEqual(store.notice?.link, .screenRecordingSettings)
    }

    func testAReadThatFindsNothingIsReportedAndTheNextCaptureIsAllowed() {
        let store = makeStore()
        store.perform(copyText)
        screen.selections[0](.success(picture))

        screen.reads[0](.failure(TextCapture.CaptureError.noTextFound))

        XCTAssertFalse(store.isReadingScreenText)
        XCTAssertEqual(store.notice?.kind, .error)
        XCTAssertEqual(store.notice?.message, "No text found in that selection.")
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertTrue(store.clips.isEmpty)
        XCTAssertTrue(store.canPerform(copyText))
    }

    /// A second capture would only queue behind the first read.
    func testAnotherCaptureIsRefusedUntilTheReadHasFinished() {
        let store = makeStore()
        store.perform(copyText)
        XCTAssertFalse(store.canPerform(copyText))
        store.perform(copyText)
        XCTAssertEqual(screen.selections.count, 1, "already selecting")

        screen.selections[0](.success(picture))
        XCTAssertFalse(store.canPerform(copyText))
        store.perform(copyText)
        XCTAssertEqual(screen.selections.count, 1, "still reading")

        screen.reads[0](.success("done"))
        XCTAssertTrue(store.canPerform(copyText))
        store.perform(copyText)
        XCTAssertEqual(screen.selections.count, 2)
    }

    func testWithHistoryOffTheTextIsCopiedButNotListed() {
        let store = makeStore()
        store.setEnabled(.clipboardHistory, false)
        store.category = .everyday
        store.perform(copyText)
        screen.selections[0](.success(picture))

        screen.reads[0](.success("kept off the list"))

        XCTAssertEqual(pasteboard.string(forType: .string), "kept off the list")
        XCTAssertTrue(store.clips.isEmpty)
        XCTAssertEqual(store.category, .everyday, "there is no list to show it in")
    }

    func testTextRecognitionIsPreparedOncePerSystemBuild() {
        let prepared = expectation(description: "recognition prepared after launch")
        screen.onPrepare = { prepared.fulfill() }
        let store = makeStore()
        wait(for: [prepared], timeout: 5)
        XCTAssertNil(defaults.string(forKey: "TextRecognitionPreparedForSystem"), "not recorded until it has worked")

        screen.preparations[0](true)
        XCTAssertEqual(defaults.string(forKey: "TextRecognitionPreparedForSystem"),
                       ProcessInfo.processInfo.operatingSystemVersionString)

        let notAgain = expectation(description: "a relaunch on the same build prepares nothing")
        notAgain.isInverted = true
        screen.onPrepare = { notAgain.fulfill() }
        let relaunched = makeStore()
        wait(for: [notAgain], timeout: 0.3)
        XCTAssertEqual(screen.preparations.count, 1)
        withExtendedLifetime((store, relaunched)) {}
    }

    func testAPreparationThatFailedIsTriedAgainAtTheNextLaunch() {
        let first = expectation(description: "first launch prepares")
        screen.onPrepare = { first.fulfill() }
        let store = makeStore()
        wait(for: [first], timeout: 5)
        screen.preparations[0](false)
        XCTAssertNil(defaults.string(forKey: "TextRecognitionPreparedForSystem"))

        let second = expectation(description: "second launch prepares again")
        screen.onPrepare = { second.fulfill() }
        let relaunched = makeStore()
        wait(for: [second], timeout: 5)
        XCTAssertEqual(screen.preparations.count, 2)
        withExtendedLifetime((store, relaunched)) {}
    }

    func testAPreparationAfterAMacOSUpdateRunsAgain() {
        defaults.set("Version 1.0 (Build OLD)", forKey: "TextRecognitionPreparedForSystem")
        let prepared = expectation(description: "a different system build prepares again")
        screen.onPrepare = { prepared.fulfill() }
        let store = makeStore()

        wait(for: [prepared], timeout: 5)
        withExtendedLifetime(store) {}
    }
}
