import AppKit
import Carbon
import XCTest

/// None of these install a real tap. A tap in the test process would act on
/// the session running the tests: flipping its mouse wheel, eating its
/// Command-Tab.
final class EventTapThreadTests: XCTestCase {
    private final class SourceProbe {
        var firings = 0
        var firedOnTapThread = false
        let fired = DispatchSemaphore(value: 0)
    }

    func testWorkRunsOnTheTapThreadAndNotTheMainThread() {
        var ranOnTapThread = false
        var ranOnMainThread = true

        EventTapThread.shared.perform {
            ranOnTapThread = EventTapThread.shared.isCurrent
            ranOnMainThread = Thread.isMainThread
        }

        XCTAssertTrue(ranOnTapThread)
        XCTAssertFalse(ranOnMainThread)
        XCTAssertFalse(EventTapThread.shared.isCurrent, "the test itself is not on the tap thread")
    }

    /// A tap callback that tears its own tap down would otherwise wait on itself.
    func testWorkAskedForFromTheTapThreadRunsInline() {
        var innerRan = false

        EventTapThread.shared.perform {
            EventTapThread.shared.perform { innerRan = true }
        }

        XCTAssertTrue(innerRan)
    }

    func testASourceFiresOnTheTapThreadUntilItIsRemoved() throws {
        let probe = SourceProbe()
        var context = CFRunLoopSourceContext()
        context.info = Unmanaged.passUnretained(probe).toOpaque()
        context.perform = { info in
            guard let info else { return }
            let probe = Unmanaged<SourceProbe>.fromOpaque(info).takeUnretainedValue()
            probe.firings += 1
            probe.firedOnTapThread = EventTapThread.shared.isCurrent
            probe.fired.signal()
        }
        let source = try XCTUnwrap(CFRunLoopSourceCreate(nil, 0, &context))

        EventTapThread.shared.add(source)
        CFRunLoopSourceSignal(source)
        EventTapThread.shared.perform {}
        XCTAssertEqual(probe.fired.wait(timeout: .now() + 2), .success)
        XCTAssertTrue(probe.firedOnTapThread)

        EventTapThread.shared.remove(source)
        CFRunLoopSourceSignal(source)
        EventTapThread.shared.perform {}
        EventTapThread.shared.perform {}
        XCTAssertEqual(probe.firings, 1, "a removed source no longer fires")
    }
}

final class ScrollInverterTests: XCTestCase {
    private func wheelEvent(units: CGScrollEventUnit, vertical: Int32, horizontal: Int32) throws -> CGEvent {
        try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                              wheel1: vertical, wheel2: horizontal, wheel3: 0))
    }

    private func deltas(of event: CGEvent) -> [Int64] {
        [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
         .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2].map(event.getIntegerValueField)
    }

    func testMouseWheelTicksAreFlippedOnBothAxes() throws {
        let event = try wheelEvent(units: .line, vertical: 3, horizontal: -2)
        let before = deltas(of: event)
        let fixedBefore = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        XCTAssertEqual(Array(before.prefix(2)), [3, -2])

        let passedOn = ScrollInverter.handle(.scrollWheel, event)

        XCTAssertTrue(passedOn?.takeUnretainedValue() === event, "the event is changed in place, never dropped")
        XCTAssertEqual(deltas(of: event), before.map { -$0 })
        // The point delta is the one AppKit reads; flipping only the line delta left it unchanged.
        XCTAssertNotEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -fixedBefore, accuracy: 0.001)
    }

    func testTrackpadScrollingIsLeftAlone() throws {
        let event = try wheelEvent(units: .pixel, vertical: 12, horizontal: 4)
        let before = deltas(of: event)

        _ = ScrollInverter.handle(.scrollWheel, event)

        XCTAssertEqual(deltas(of: event), before)
    }

    /// A Magic Mouse sends wheel-like deltas with a gesture phase. It follows
    /// the trackpad setting, so it is not flipped either.
    func testAGestureWithAPhaseIsLeftAlone() throws {
        for phaseField in [CGEventField.scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase] {
            let event = try wheelEvent(units: .line, vertical: 3, horizontal: 0)
            event.setIntegerValueField(phaseField, value: 1)
            let before = deltas(of: event)

            _ = ScrollInverter.handle(.scrollWheel, event)

            XCTAssertEqual(deltas(of: event), before)
        }
    }

    func testOtherEventTypesPassThroughUnchanged() throws {
        let event = try wheelEvent(units: .line, vertical: 3, horizontal: 0)
        let before = deltas(of: event)

        let passedOn = ScrollInverter.handle(.keyDown, event)

        XCTAssertTrue(passedOn?.takeUnretainedValue() === event)
        XCTAssertEqual(deltas(of: event), before)
    }

    func testAStationaryWheelEventStaysStationary() throws {
        let event = try wheelEvent(units: .line, vertical: 0, horizontal: 0)

        _ = ScrollInverter.handle(.scrollWheel, event)

        XCTAssertEqual(deltas(of: event), [0, 0, 0, 0])
    }
}

/// The rule that decides which key presses never reach any other app.
final class CommandTabVerdictTests: XCTestCase {
    private let tab = Int64(kVK_Tab)
    private let bindings: [UInt32: GlobalShortcut] = [
        1: GlobalShortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey)),
        2: GlobalShortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(cmdKey | shiftKey))
    ]

    private func verdict(_ type: CGEventType, key: Int64, flags: CGEventFlags = [],
                         pressed: UInt32? = nil) -> CommandTabHotKeys.KeyVerdict {
        CommandTabHotKeys.verdict(type: type, keyCode: key, flags: flags, bindings: bindings, pressedID: pressed)
    }

    func testCommandTabAndItsReverseAreClaimed() {
        XCTAssertEqual(verdict(.keyDown, key: tab, flags: .maskCommand), .press(1))
        XCTAssertEqual(verdict(.keyDown, key: tab, flags: [.maskCommand, .maskShift]), .press(2))
    }

    func testCapsLockDoesNotBreakTheChord() {
        XCTAssertEqual(verdict(.keyDown, key: tab, flags: [.maskCommand, .maskAlphaShift]), .press(1))
    }

    func testEveryOtherKeyIsPassedOn() {
        XCTAssertEqual(verdict(.keyDown, key: tab), .pass, "Tab alone is typing")
        XCTAssertEqual(verdict(.keyDown, key: tab, flags: [.maskCommand, .maskAlternate]), .pass)
        XCTAssertEqual(verdict(.keyDown, key: Int64(kVK_ANSI_Q), flags: .maskCommand), .pass)
        XCTAssertEqual(verdict(.flagsChanged, key: tab, flags: .maskCommand), .pass)
        XCTAssertEqual(verdict(.keyDown, key: -1, flags: .maskCommand), .pass)
    }

    func testReleasingTabEndsTheChordThatWasPressed() {
        XCTAssertEqual(verdict(.keyUp, key: tab, pressed: 2), .release(2))
        XCTAssertEqual(verdict(.keyUp, key: tab, flags: .maskCommand, pressed: 1), .release(1))
    }

    func testAReleaseWithNothingPressedIsPassedOn() {
        XCTAssertEqual(verdict(.keyUp, key: tab), .pass)
        XCTAssertEqual(verdict(.keyUp, key: Int64(kVK_ANSI_Q), pressed: 1), .pass, "only Tab ends the chord")
    }

    func testNoBindingsClaimNothing() {
        XCTAssertEqual(CommandTabHotKeys.verdict(type: .keyDown, keyCode: tab, flags: .maskCommand,
                                                 bindings: [:], pressedID: nil), .pass)
    }
}

final class ShortcutFromEventFlagsTests: XCTestCase {
    func testAKeySeenByATapEqualsTheSameKeySeenByAppKit() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                   modifierFlags: [.command, .option, .shift, .control],
                                                   timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                                   charactersIgnoringModifiers: "", isARepeat: false, keyCode: 40))

        let fromAppKit = GlobalShortcut(event: event)

        XCTAssertEqual(fromAppKit, GlobalShortcut(keyCode: 40, flags: [.maskCommand, .maskAlternate, .maskShift, .maskControl]))
        XCTAssertEqual(fromAppKit.modifiers, UInt32(cmdKey | optionKey | shiftKey | controlKey))
    }

    /// Arrow and function keys report Fn whether or not it is held, so it
    /// only counts as a modifier on the keys that do not.
    func testFnCountsOnlyOnKeysThatDoNotCarryItThemselves() {
        let letter = GlobalShortcut(keyCode: 40, flags: [.maskControl, .maskSecondaryFn])
        XCTAssertEqual(letter.modifiers, UInt32(controlKey) | UInt32(kEventKeyModifierFnMask))
        XCTAssertNotNil(letter.validationError)

        let arrow = GlobalShortcut(keyCode: UInt32(kVK_LeftArrow), flags: [.maskControl, .maskSecondaryFn])
        XCTAssertEqual(arrow.modifiers, UInt32(controlKey))
    }

    func testNoModifiersGiveNone() {
        XCTAssertEqual(GlobalShortcut(keyCode: 40, flags: []).modifiers, 0)
    }
}
