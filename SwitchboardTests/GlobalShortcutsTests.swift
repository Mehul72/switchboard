import AppKit
import Carbon
import XCTest

@MainActor
final class GlobalShortcutsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var registrar: TestHotKeyRegistrar!

    override func setUp() {
        super.setUp()
        suite = "Switchboard.ShortcutsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        registrar = TestHotKeyRegistrar()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        registrar = nil
        defaults = nil
        super.tearDown()
    }

    func testFirstLaunchRegistersFourDistinctDefaults() {
        let shortcuts = makeShortcuts()
        XCTAssertEqual(shortcuts.bindings.count, 4)
        XCTAssertEqual(Set(registrar.bindings.values).count, 4)
        XCTAssertTrue(shortcuts.errors.isEmpty)
    }

    func testEditingAndDisablingSurviveRelaunch() throws {
        let shortcuts = makeShortcuts()
        let replacement = GlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey))
        XCTAssertTrue(shortcuts.set(replacement, for: .togglePanel))
        XCTAssertTrue(shortcuts.set(nil, for: .clipboard))
        XCTAssertFalse(registrar.bindings.values.contains(ShortcutAction.togglePanel.defaultShortcut))

        let relaunched = GlobalShortcuts(defaults: defaults, registrar: TestHotKeyRegistrar())
        XCTAssertEqual(relaunched.bindings[.togglePanel], replacement)
        XCTAssertNil(relaunched.bindings[.clipboard])
        XCTAssertEqual(relaunched.bindings[.captureText], ShortcutAction.captureText.defaultShortcut)
    }

    func testDuplicateDoesNotReplaceWorkingBindingOrPersist() {
        let shortcuts = makeShortcuts()
        XCTAssertFalse(shortcuts.set(ShortcutAction.clipboard.defaultShortcut, for: .togglePanel))
        XCTAssertEqual(shortcuts.bindings[.togglePanel], ShortcutAction.togglePanel.defaultShortcut)
        XCTAssertNotNil(shortcuts.errors[.togglePanel])
        XCTAssertNil(defaults.object(forKey: GlobalShortcuts.preferenceKey(for: .togglePanel)))
        XCTAssertEqual(registrar.bindings.count, 4)
    }

    func testRegistrationFailurePreservesPreviousBindingAndStorage() {
        let shortcuts = makeShortcuts()
        let replacement = GlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey))
        registrar.rejected.insert(replacement)
        XCTAssertFalse(shortcuts.set(replacement, for: .togglePanel))
        XCTAssertEqual(shortcuts.bindings[.togglePanel], ShortcutAction.togglePanel.defaultShortcut)
        XCTAssertTrue(registrar.bindings.values.contains(ShortcutAction.togglePanel.defaultShortcut))
        XCTAssertNil(defaults.object(forKey: GlobalShortcuts.preferenceKey(for: .togglePanel)))
    }

    func testUnregisterFailureRollsBackReplacement() {
        let shortcuts = makeShortcuts()
        registrar.failedRemoval = id(for: .togglePanel)
        XCTAssertFalse(shortcuts.set(GlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey)),
                                     for: .togglePanel))
        XCTAssertEqual(registrar.bindings.count, 4)
        XCTAssertEqual(shortcuts.bindings[.togglePanel], ShortcutAction.togglePanel.defaultShortcut)
        XCTAssertNil(defaults.object(forKey: GlobalShortcuts.preferenceKey(for: .togglePanel)))
    }

    func testInvalidAndUnreadableSavedBindingsStayInactive() {
        defaults.set(Data(#"{"keyCode":4294967295,"modifiers":0}"#.utf8),
                     forKey: GlobalShortcuts.preferenceKey(for: .togglePanel))
        defaults.set(Data("broken".utf8), forKey: GlobalShortcuts.preferenceKey(for: .clipboard))
        let shortcuts = makeShortcuts()
        XCTAssertNil(shortcuts.bindings[.togglePanel])
        XCTAssertNil(shortcuts.bindings[.clipboard])
        XCTAssertEqual(shortcuts.errors.count, 2)
        XCTAssertEqual(registrar.bindings.count, 2)
    }

    func testDuplicateSavedBindingsOnlyActivateOneAction() throws {
        let data = try JSONEncoder().encode(ShortcutAction.togglePanel.defaultShortcut)
        defaults.set(data, forKey: GlobalShortcuts.preferenceKey(for: .clipboard))
        let shortcuts = makeShortcuts()
        XCTAssertEqual(registrar.bindings.count, 3)
        XCTAssertNotNil(shortcuts.errors[.clipboard])
    }

    func testUnavailableBindingCanBeRetried() {
        registrar.rejected.insert(ShortcutAction.togglePanel.defaultShortcut)
        let shortcuts = makeShortcuts()
        XCTAssertNotNil(shortcuts.errors[.togglePanel])
        registrar.rejected.removeAll()
        shortcuts.retryUnavailable()
        XCTAssertEqual(registrar.bindings.count, 4)
        XCTAssertTrue(shortcuts.errors.isEmpty)
        shortcuts.retryUnavailable()
        XCTAssertEqual(registrar.bindings.count, 4)
    }

    func testHeldKeyFiresOnceOnRelease() {
        let shortcuts = makeShortcuts()
        var actions: [ShortcutAction] = []
        shortcuts.onAction = { actions.append($0) }
        let key = id(for: .toggleAwake)
        registrar.onEvent?(key, true)
        registrar.onEvent?(key, true)
        XCTAssertTrue(actions.isEmpty)
        registrar.onEvent?(key, false)
        registrar.onEvent?(key, false)
        XCTAssertEqual(actions, [.toggleAwake])
    }

    func testAllFourActionsDispatchToTheirOwnHandler() {
        let shortcuts = makeShortcuts()
        var actions: [ShortcutAction] = []
        shortcuts.onAction = { actions.append($0) }
        for action in ShortcutAction.allCases {
            registrar.onEvent?(id(for: action), true)
            registrar.onEvent?(id(for: action), false)
        }
        XCTAssertEqual(actions, ShortcutAction.allCases)
    }

    func testDisabledAndReplacedBindingsCannotDispatchQueuedEvents() {
        let shortcuts = makeShortcuts()
        var actions: [ShortcutAction] = []
        shortcuts.onAction = { actions.append($0) }
        let oldID = id(for: .togglePanel)
        registrar.onEvent?(oldID, true)
        XCTAssertTrue(shortcuts.set(nil, for: .togglePanel))
        registrar.onEvent?(oldID, false)
        registrar.onEvent?(oldID, true)
        registrar.onEvent?(oldID, false)
        XCTAssertTrue(actions.isEmpty)
    }

    func testRecordingAnExistingBindingReportsDuplicateWithoutExecutingIt() {
        let shortcuts = makeShortcuts()
        var actions: [ShortcutAction] = []
        shortcuts.onAction = { actions.append($0) }
        shortcuts.beginRecording(.togglePanel)
        registrar.onEvent?(id(for: .clipboard), true)
        registrar.onEvent?(id(for: .clipboard), false)
        XCTAssertNotNil(shortcuts.errors[.togglePanel])
        XCTAssertEqual(shortcuts.recordingAction, .togglePanel)
        XCTAssertTrue(actions.isEmpty)
    }

    func testLeavingRecorderBeforeReleaseDoesNotTriggerAnAction() {
        let shortcuts = makeShortcuts()
        var actions: [ShortcutAction] = []
        shortcuts.onAction = { actions.append($0) }
        shortcuts.beginRecording(.togglePanel)
        registrar.onEvent?(id(for: .clipboard), true)
        shortcuts.cancelRecording()
        registrar.onEvent?(id(for: .clipboard), false)
        XCTAssertTrue(actions.isEmpty)
    }

    func testRecordingCanBeCancelledOrCleared() {
        let shortcuts = makeShortcuts()
        shortcuts.beginRecording(.togglePanel)
        shortcuts.cancelRecording()
        XCTAssertEqual(shortcuts.bindings[.togglePanel], ShortcutAction.togglePanel.defaultShortcut)
        shortcuts.beginRecording(.togglePanel)
        shortcuts.record(nil)
        XCTAssertNil(shortcuts.bindings[.togglePanel])
        XCTAssertNil(shortcuts.recordingAction)
    }

    func testUnsafeOrUnsupportedCombinationsAreRejected() {
        for shortcut in [
            GlobalShortcut(keyCode: 0, modifiers: 0),
            GlobalShortcut(keyCode: 0, modifiers: UInt32(shiftKey)),
            GlobalShortcut(keyCode: 0, modifiers: UInt32(cmdKey)),
            GlobalShortcut(keyCode: 0, modifiers: .max),
            GlobalShortcut(keyCode: 55, modifiers: UInt32(cmdKey | shiftKey)),
            GlobalShortcut(keyCode: .max, modifiers: UInt32(cmdKey | shiftKey))
        ] {
            XCTAssertNotNil(shortcut.validationError)
        }
        for modifiers in [cmdKey | shiftKey, controlKey, optionKey, optionKey | shiftKey, controlKey | shiftKey] {
            XCTAssertNil(GlobalShortcut(keyCode: 0, modifiers: UInt32(modifiers)).validationError)
        }
    }

    private func makeShortcuts() -> GlobalShortcuts {
        GlobalShortcuts(defaults: defaults, registrar: registrar)
    }

    private func id(for action: ShortcutAction) -> UInt32 {
        registrar.bindings.first { $0.value == action.defaultShortcut }!.key
    }
}

@MainActor
private final class TestHotKeyRegistrar: HotKeyRegistering {
    var onEvent: ((UInt32, Bool) -> Void)?
    var bindings: [UInt32: GlobalShortcut] = [:]
    var rejected: Set<GlobalShortcut> = []
    var failedRemoval: UInt32?

    func register(_ shortcut: GlobalShortcut, id: UInt32) throws {
        if rejected.contains(shortcut) { throw HotKeyError.unavailable(OSStatus(eventHotKeyExistsErr)) }
        bindings[id] = shortcut
    }

    func unregister(id: UInt32) throws {
        if id == failedRemoval { throw HotKeyError.unavailable(OSStatus(paramErr)) }
        bindings[id] = nil
    }
}

@MainActor
final class NativeHotKeyTests: XCTestCase {
    func testNativeRegistrationDispatchAndCleanup() throws {
        let registrar = HotKeyRegistrar()
        let binding = GlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        try registrar.register(binding, id: 701)
        defer { XCTAssertNoThrow(try registrar.unregister(id: 701)) }
        var received: [Bool] = []
        registrar.onEvent = { id, pressed in
            XCTAssertEqual(id, 701)
            received.append(pressed)
        }
        try sendEvent(id: 701, kind: UInt32(kEventHotKeyPressed))
        try sendEvent(id: 701, kind: UInt32(kEventHotKeyReleased))
        XCTAssertEqual(received, [true, false])

        try registrar.unregister(id: 701)
        let other = HotKeyRegistrar()
        XCTAssertNoThrow(try other.register(binding, id: 702))
        XCTAssertNoThrow(try other.unregister(id: 702))
    }

    func testNativeRegistrationReportsAnotherRegistration() throws {
        let first = HotKeyRegistrar()
        let second = HotKeyRegistrar()
        let binding = GlobalShortcut(keyCode: 37, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        try first.register(binding, id: 703)
        defer { XCTAssertNoThrow(try first.unregister(id: 703)) }
        XCTAssertThrowsError(try second.register(binding, id: 704))
    }

    private func sendEvent(id: UInt32, kind: UInt32) throws {
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), kind, 0,
                                   EventAttributes(kEventAttributeUserEvent), &event), noErr)
        let unwrapped = try XCTUnwrap(event)
        defer { ReleaseEvent(unwrapped) }
        var identifier = EventHotKeyID(signature: HotKeyRegistrar.signature, id: id)
        XCTAssertEqual(SetEventParameter(unwrapped, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
        XCTAssertEqual(SendEventToEventTarget(unwrapped, GetApplicationEventTarget()), noErr)
    }
}

@MainActor
final class ShortcutEditorTests: XCTestCase {
    func testRecorderOnlyAcceptsEventsForItsOwnKeyWindow() throws {
        try withRunningApplication { try self.checkRecorderWindowScope() }
    }

    func testEscapeTabDeleteAndWindowCloseEndRecording() throws {
        try withRunningApplication { try self.checkRecorderLifecycle() }
    }

    private func checkRecorderWindowScope() throws {
        let suite = "Switchboard.ShortcutEditorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = GlobalShortcuts(defaults: defaults, registrar: TestHotKeyRegistrar())
        let editor = ShortcutSettingsController(shortcuts: shortcuts)
        editor.open()
        let window = try XCTUnwrap(editor.window)
        defer { window.close() }
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.isKeyWindow)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.contentLayoutRect.height, 530, accuracy: 0.1)
        XCTAssertEqual(window.contentLayoutRect.width, 620, accuracy: 0.1)

        shortcuts.beginRecording(.togglePanel)
        let otherWindow = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        let outsideEvent = try keyEvent(code: 40, window: otherWindow)
        XCTAssertNotNil(editor.handleKey(outsideEvent))
        XCTAssertEqual(shortcuts.recordingAction, .togglePanel)

        let event = try keyEvent(code: 40, window: window)
        XCTAssertNil(editor.handleKey(event))
        XCTAssertEqual(shortcuts.bindings[.togglePanel],
                       GlobalShortcut(keyCode: 40, modifiers: UInt32(cmdKey | optionKey)))
        XCTAssertNil(shortcuts.recordingAction)
    }

    private func checkRecorderLifecycle() throws {
        let suite = "Switchboard.ShortcutEditorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = GlobalShortcuts(defaults: defaults, registrar: TestHotKeyRegistrar())
        let editor = ShortcutSettingsController(shortcuts: shortcuts)
        editor.open()
        let window = try XCTUnwrap(editor.window)
        defer { window.close() }

        shortcuts.beginRecording(.togglePanel)
        XCTAssertNil(editor.handleKey(try keyEvent(code: UInt16(kVK_Escape), flags: [], window: window)))
        XCTAssertNil(shortcuts.recordingAction)
        XCTAssertEqual(shortcuts.bindings[.togglePanel], ShortcutAction.togglePanel.defaultShortcut)

        shortcuts.beginRecording(.togglePanel)
        XCTAssertNotNil(editor.handleKey(try keyEvent(code: UInt16(kVK_Tab), flags: [], window: window)))
        XCTAssertNil(shortcuts.recordingAction)

        shortcuts.beginRecording(.togglePanel)
        XCTAssertNil(editor.handleKey(try keyEvent(code: UInt16(kVK_Delete), flags: [], window: window)))
        XCTAssertNil(shortcuts.recordingAction)
        XCTAssertNil(shortcuts.bindings[.togglePanel])

        shortcuts.beginRecording(.clipboard)
        window.performClose(nil)
        XCTAssertNil(shortcuts.recordingAction)
        XCTAssertFalse(window.isVisible)
    }

    private func withRunningApplication(_ body: @escaping () throws -> Void) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var failure: Error?
        let stop = {
            app.stop(nil)
            let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                                         modifierFlags: [], timestamp: 0, windowNumber: 0,
                                         context: nil, subtype: 0, data1: 0, data2: 0)!
            app.postEvent(wake, atStart: true)
        }
        let execute = {
            do { try body() }
            catch { failure = error }
            stop()
        }
        // The first activation is asynchronous; later tests may already own the foreground.
        var observer: NSObjectProtocol?
        if app.isActive {
            DispatchQueue.main.async { execute() }
        } else {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: app, queue: .main
            ) { _ in DispatchQueue.main.async { execute() } }
            DispatchQueue.main.async { app.activate(ignoringOtherApps: true) }
        }
        let timeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            XCTFail("The test application did not become active.")
            stop()
        }
        defer {
            timeout.invalidate()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
        app.run()
        if let failure { throw failure }
    }

    private func keyEvent(code: UInt16, flags: NSEvent.ModifierFlags = [.command, .option],
                          window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                      timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      characters: "", charactersIgnoringModifiers: "",
                                      isARepeat: false, keyCode: code))
    }
}
