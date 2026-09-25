import AppKit
import XCTest

final class ShelfDragGestureTests: XCTestCase {
    private func zigzag(swing: CGFloat, stepSeconds: TimeInterval, swings: Int) -> [(CGPoint, TimeInterval)] {
        (0...swings).map { index in
            (CGPoint(x: index.isMultiple(of: 2) ? 500 : 500 + swing, y: 400), TimeInterval(index) * stepSeconds)
        }
    }

    private func firstShake(_ samples: [(CGPoint, TimeInterval)]) -> Int? {
        var detector = ShakeDetector()
        return samples.firstIndex { detector.add($0.0, at: $0.1) }
    }

    func testQuickWideShakeIsDetected() {
        XCTAssertEqual(firstShake(zigzag(swing: 80, stepSeconds: 0.1, swings: 6)), 3)
        XCTAssertEqual(firstShake(zigzag(swing: 32, stepSeconds: 0.12, swings: 4)), 3)
    }

    func testVerticalShakeIsDetected() {
        var detector = ShakeDetector()
        let hits = (0...6).map { detector.add(CGPoint(x: 300, y: $0.isMultiple(of: 2) ? 300 : 380), at: Double($0) * 0.1) }
        XCTAssertTrue(hits.contains(true))
    }

    func testStraightDragJitterAndSlowWavingAreNotShakes() {
        let straight = (0...60).map { (CGPoint(x: 100 + CGFloat($0) * 12, y: 400), TimeInterval($0) / 60) }
        XCTAssertNil(firstShake(straight))
        XCTAssertNil(firstShake(zigzag(swing: 24, stepSeconds: 0.05, swings: 12)))
        XCTAssertNil(firstShake(zigzag(swing: 80, stepSeconds: 0.1, swings: 2)), "One correction is aiming, not a shake")
        XCTAssertNil(firstShake(zigzag(swing: 120, stepSeconds: 0.6, swings: 8)), "Slow aiming back and forth")
    }

    func testShakeOnlyTriggersForFileDragsAndOnlyOnce() {
        var session = ShelfDragSession(modifiers: [])
        let samples = zigzag(swing: 80, stepSeconds: 0.1, swings: 12)
        let withoutFiles = samples.compactMap { session.sample($0.0, at: $0.1, modifiers: [], isFileDrag: false) }
        XCTAssertTrue(withoutFiles.isEmpty)

        session = ShelfDragSession(modifiers: [])
        let triggers = samples.compactMap { session.sample($0.0, at: $0.1, modifiers: [], isFileDrag: true) }
        XCTAssertEqual(triggers, [.shake])
    }

    func testPressingShiftDuringFileDragTriggers() {
        var session = ShelfDragSession(modifiers: [])
        let point = CGPoint(x: 10, y: 10)
        XCTAssertNil(session.sample(point, at: 0, modifiers: [], isFileDrag: true))
        XCTAssertEqual(session.sample(point, at: 0.1, modifiers: .shift, isFileDrag: true), .shiftKey)
        XCTAssertNil(session.sample(point, at: 0.2, modifiers: [], isFileDrag: true))
        XCTAssertNil(session.sample(point, at: 0.3, modifiers: .shift, isFileDrag: true))
    }

    func testShiftHeldFromTheStartOrWithOtherModifiersDoesNotTrigger() {
        let point = CGPoint(x: 10, y: 10)
        var held = ShelfDragSession(modifiers: .shift)
        XCTAssertNil(held.sample(point, at: 0, modifiers: .shift, isFileDrag: true))
        XCTAssertNil(held.sample(point, at: 0.1, modifiers: .shift, isFileDrag: true))

        var combined = ShelfDragSession(modifiers: [])
        XCTAssertNil(combined.sample(point, at: 0, modifiers: [.shift, .command], isFileDrag: true))
        XCTAssertNil(combined.sample(point, at: 0.1, modifiers: [.shift, .option], isFileDrag: true))
    }

    func testPanelOpensBesidePointerAndStaysOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height: CGFloat = 700
        let width = FileShelfController.width
        for pointer in [NSPoint(x: 200, y: 450), NSPoint(x: 1430, y: 450), NSPoint(x: 5, y: 5), NSPoint(x: 1435, y: 895)] {
            let origin = FileShelfController.origin(beside: pointer, height: height, in: screen)
            let frame = NSRect(origin: origin, size: NSSize(width: width, height: height))
            XCTAssertTrue(screen.insetBy(dx: 7, dy: 7).contains(frame), "\(pointer) → \(frame)")
            XCTAssertFalse(frame.contains(pointer), "Pointer must start outside the panel at \(pointer)")
        }
    }
}
