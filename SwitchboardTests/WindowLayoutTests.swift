import CoreGraphics
import XCTest

final class WindowLayoutTests: XCTestCase {
    /// Odd sizes and a non-zero origin, like a secondary display under a menu bar.
    private let screen = CGRect(x: 1440, y: 25, width: 1001, height: 767)
    private let window = CGRect(x: 1500, y: 100, width: 400, height: 300)

    private func frame(_ placement: WindowPlacement) -> CGRect {
        WindowLayout.frame(for: placement, window: window, in: screen)
    }

    func testHalvesTileTheScreenWithoutGapsOrOverlap() {
        let left = frame(.leftHalf), right = frame(.rightHalf)
        XCTAssertEqual(left.minX, screen.minX)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(right.maxX, screen.maxX)
        XCTAssertEqual(left.height, screen.height)

        let top = frame(.topHalf), bottom = frame(.bottomHalf)
        XCTAssertEqual(top.minY, screen.minY)
        XCTAssertEqual(top.maxY, bottom.minY)
        XCTAssertEqual(bottom.maxY, screen.maxY)
    }

    func testThirdsTileAndTwoThirdsShareTheirBoundaries() {
        let left = frame(.leftThird), middle = frame(.centerThird), right = frame(.rightThird)
        XCTAssertEqual(left.minX, screen.minX)
        XCTAssertEqual(left.maxX, middle.minX)
        XCTAssertEqual(middle.maxX, right.minX)
        XCTAssertEqual(right.maxX, screen.maxX)
        XCTAssertEqual(frame(.leftTwoThirds), CGRect(x: left.minX, y: screen.minY,
                                                     width: middle.maxX - left.minX, height: screen.height))
        XCTAssertEqual(frame(.rightTwoThirds).minX, middle.minX)
        XCTAssertEqual(frame(.rightTwoThirds).maxX, screen.maxX)
    }

    func testQuartersCoverTheScreenExactly() {
        let quarters = [frame(.topLeft), frame(.topRight), frame(.bottomLeft), frame(.bottomRight)]
        XCTAssertEqual(quarters.map { $0.width * $0.height }.reduce(0, +), screen.width * screen.height)
        XCTAssertEqual(quarters.reduce(CGRect.null) { $0.union($1) }, screen)
        XCTAssertEqual(frame(.topLeft).maxX, frame(.topRight).minX)
        XCTAssertEqual(frame(.topLeft).maxY, frame(.bottomLeft).minY)
    }

    func testMaximiseFillsTheVisibleFrame() {
        XCTAssertEqual(frame(.maximize), screen)
    }

    func testCentreKeepsSizeAndShrinksOversizedWindows() {
        let centred = frame(.center)
        XCTAssertEqual(centred.size, window.size)
        XCTAssertEqual(centred.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(centred.midY, screen.midY, accuracy: 1)

        let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
        XCTAssertEqual(WindowLayout.frame(for: .center, window: huge, in: screen), screen)
    }

    func testFittedSlidesAnEnlargedWindowBackOnScreen() {
        let overhanging = CGRect(x: screen.maxX - 200, y: screen.maxY - 100, width: 600, height: 400)
        let fitted = WindowLayout.fitted(overhanging, in: screen)
        XCTAssertEqual(fitted.maxX, screen.maxX)
        XCTAssertEqual(fitted.maxY, screen.maxY)
        XCTAssertEqual(fitted.size, overhanging.size)
    }

    func testFixedSizeWindowsHugTheEdgesTheirPlacementTouches() {
        let size = CGSize(width: 300, height: 200)
        let topRight = WindowLayout.anchored(size, within: frame(.topRight), on: screen)
        XCTAssertEqual(topRight.maxX, screen.maxX)
        XCTAssertEqual(topRight.minY, screen.minY)

        let bottomLeft = WindowLayout.anchored(size, within: frame(.bottomLeft), on: screen)
        XCTAssertEqual(bottomLeft.minX, screen.minX)
        XCTAssertEqual(bottomLeft.maxY, screen.maxY)

        let middle = WindowLayout.anchored(size, within: frame(.centerThird), on: screen)
        XCTAssertEqual(middle.midX, frame(.centerThird).midX, accuracy: 1)
        XCTAssertEqual(middle.minY, screen.minY)

        let tooBig = WindowLayout.anchored(CGSize(width: 2000, height: 1000), within: frame(.rightHalf), on: screen)
        XCTAssertEqual(tooBig.origin, screen.origin)
    }

    func testFittedPinsWindowsLargerThanTheScreenToItsTopLeft() {
        let giant = CGRect(x: 1800, y: 300, width: 2000, height: 1000)
        XCTAssertEqual(WindowLayout.fitted(giant, in: screen).origin, screen.origin)
    }

    func testMovingKeepsRelativePlacementOnADifferentlySizedDisplay() {
        let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let leftHalf = WindowLayout.frame(for: .leftHalf, window: window, in: laptop)
        let moved = WindowLayout.frame(movedFrom: laptop, to: screen, window: leftHalf)
        XCTAssertEqual(moved.minX, screen.minX)
        XCTAssertEqual(moved.minY, screen.minY)
        XCTAssertEqual(moved.width, screen.width / 2, accuracy: 1)
        XCTAssertEqual(moved.height, screen.height)
    }

    func testScreenIndexPrefersLargestOverlapThenNearestDisplay() {
        let displays = [CGRect(x: 0, y: 0, width: 1000, height: 800), screen]
        let straddling = CGRect(x: 900, y: 100, width: 800, height: 300)
        XCTAssertEqual(WindowLayout.screenIndex(for: straddling, among: displays), 1)
        let lost = CGRect(x: -3000, y: 100, width: 200, height: 200)
        XCTAssertEqual(WindowLayout.screenIndex(for: lost, among: displays), 0)
        XCTAssertNil(WindowLayout.screenIndex(for: window, among: []))
    }

    func testNeighbourCyclesInSpatialOrderAndNeedsTwoDisplays() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let displays = [main, right, left]
        XCTAssertEqual(WindowLayout.neighbourIndex(of: 0, among: displays, forward: true), 1)
        XCTAssertEqual(WindowLayout.neighbourIndex(of: 1, among: displays, forward: true), 2)
        XCTAssertEqual(WindowLayout.neighbourIndex(of: 2, among: displays, forward: false), 1)
        XCTAssertNil(WindowLayout.neighbourIndex(of: 0, among: [main], forward: true))
        XCTAssertNil(WindowLayout.neighbourIndex(of: 5, among: displays, forward: true))
    }

    func testAppKitRectsFlipAroundThePrimaryDisplay() {
        let menuBarless = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(WindowLayout.accessibilityRect(fromAppKit: menuBarless, primaryScreenHeight: 900),
                       CGRect(x: 0, y: 25, width: 1440, height: 875))
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        XCTAssertEqual(WindowLayout.accessibilityRect(fromAppKit: above, primaryScreenHeight: 900).minY, -1080)
    }

    func testDestinationUsesTheWindowsOwnDisplayOrItsNeighbour() {
        let main = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let displays = [main, screen]
        let onMain = CGRect(x: 100, y: 100, width: 400, height: 300)

        let placed = WindowLayout.destination(of: .place(.rightHalf), window: onMain, screens: displays)
        XCTAssertEqual(placed?.screen, main)
        XCTAssertEqual(placed?.frame, WindowLayout.frame(for: .rightHalf, window: onMain, in: main))

        let moved = WindowLayout.destination(of: .nextDisplay, window: onMain, screens: displays)
        XCTAssertEqual(moved?.screen, screen)
        XCTAssertEqual(WindowLayout.destination(of: .previousDisplay, window: onMain, screens: displays)?.screen,
                       screen, "two displays wrap around in both directions")

        XCTAssertNil(WindowLayout.destination(of: .nextDisplay, window: onMain, screens: [main]))
        XCTAssertNil(WindowLayout.destination(of: .restore, window: onMain, screens: displays))
        XCTAssertNil(WindowLayout.destination(of: .place(.maximize), window: onMain, screens: []))
    }

    func testLeftWalksFromFullScreenToHalfThenThird() {
        XCTAssertEqual(LayoutCell(.full, .full).stepped(.left), LayoutCell(.leftHalf, .full))
        XCTAssertEqual(LayoutCell(.leftHalf, .full).stepped(.left), LayoutCell(.leftThird, .full))
        XCTAssertNil(LayoutCell(.leftThird, .full).stepped(.left))
        XCTAssertEqual(LayoutCell(.rightHalf, .top).stepped(.left), LayoutCell(.full, .top))
    }

    func testThirdsWalkAmongThemselves() {
        XCTAssertEqual(LayoutCell(.leftThird, .full).stepped(.right), LayoutCell(.centerThird, .full))
        XCTAssertEqual(LayoutCell(.centerThird, .full).stepped(.right), LayoutCell(.rightThird, .full))
        XCTAssertNil(LayoutCell(.rightThird, .full).stepped(.right))
        XCTAssertEqual(LayoutCell(.rightThird, .bottom).stepped(.left), LayoutCell(.centerThird, .bottom))
        XCTAssertEqual(LayoutCell(.centerThird, .full).stepped(.left), LayoutCell(.leftThird, .full))
    }

    func testUpReachesFullScreenInOnePressFromEveryOtherLayout() {
        for cell in LayoutCell.all where cell != LayoutCell.fullScreen {
            XCTAssertEqual(cell.stepped(.up), LayoutCell.fullScreen, "\(cell)")
        }
        XCTAssertEqual(LayoutCell.fullScreen.stepped(.up), LayoutCell(.full, .top))
        XCTAssertEqual(LayoutCell.starting(.up), LayoutCell.fullScreen)
    }

    func testDownRejoinsTopRowsThenHalvesDownwards() {
        XCTAssertEqual(LayoutCell(.leftHalf, .top).stepped(.down), LayoutCell(.leftHalf, .full))
        XCTAssertEqual(LayoutCell(.leftHalf, .full).stepped(.down), LayoutCell(.leftHalf, .bottom))
        XCTAssertEqual(LayoutCell(.full, .top).stepped(.down), LayoutCell.fullScreen)
        XCTAssertEqual(LayoutCell.fullScreen.stepped(.down), LayoutCell(.full, .bottom))
        XCTAssertNil(LayoutCell(.rightThird, .bottom).stepped(.down))
    }

    func testTopRowLayoutsAreReachedFromFullScreenUpThenSideways() {
        let topHalf = LayoutCell.fullScreen.stepped(.up)
        XCTAssertEqual(topHalf?.stepped(.left), LayoutCell(.leftHalf, .top))
        XCTAssertEqual(topHalf?.stepped(.left)?.stepped(.left), LayoutCell(.leftThird, .top))
        XCTAssertEqual(topHalf?.stepped(.right)?.stepped(.right)?.stepped(.left), LayoutCell(.centerThird, .top))
    }

    func testEveryLayoutIsReachableFromEveryStart() {
        let directions: [StepDirection] = [.left, .right, .up, .down]
        var reached = Set(directions.map(LayoutCell.starting))
        var frontier = Array(reached)
        while let cell = frontier.popLast() {
            for next in directions.compactMap(cell.stepped) where reached.insert(next).inserted {
                frontier.append(next)
            }
        }
        XCTAssertEqual(reached, Set(LayoutCell.all))
    }

    func testSidewaysStepsCanBeUndoneByTheOppositeArrowExceptIntoThirds() {
        let opposite: [StepDirection: StepDirection] = [.left: .right, .right: .left]
        for cell in LayoutCell.all {
            for (direction, back) in opposite {
                guard let next = cell.stepped(direction) else { continue }
                let thirds: Set<LayoutCell.Columns> = [.leftThird, .centerThird, .rightThird]
                // Left half to left third, then right, lands on the centre third.
                if thirds.contains(next.columns), !thirds.contains(cell.columns) { continue }
                XCTAssertEqual(next.stepped(back), cell, "\(cell) \(direction)")
            }
        }
    }

    func testCellFramesMatchPlacementsAndAreRecognised() {
        for placement in WindowPlacement.allCases {
            guard let cell = placement.cell else { continue }
            XCTAssertEqual(WindowLayout.frame(for: cell, in: screen), frame(placement))
        }
        for cell in LayoutCell.all {
            let nudged = WindowLayout.frame(for: cell, in: screen).offsetBy(dx: 1, dy: -1)
            XCTAssertEqual(WindowLayout.cell(matching: nudged, in: screen), cell)
        }
        XCTAssertNil(WindowLayout.cell(matching: window, in: screen))
        XCTAssertNil(WindowLayout.cell(matching: frame(.leftTwoThirds), in: screen))
    }

    func testMemoryKeepsTheLayoutOnlyWhileTheWindowStaysPut() {
        var memory = SnapMemory<String>()
        let terminalLeftHalf = frame(.leftHalf).insetBy(dx: 0, dy: 7)
        memory.recordSnap(of: "term", from: window, to: terminalLeftHalf, cell: LayoutCell(.leftHalf, .full))
        XCTAssertEqual(memory.cell(of: "term", at: terminalLeftHalf), LayoutCell(.leftHalf, .full))
        XCTAssertNil(memory.cell(of: "term", at: window))
        XCTAssertNil(memory.cell(of: "other", at: terminalLeftHalf))
    }

    func testGridSpansOfThreeAndTwoCellsAreHalvesAndThirds() {
        let top = 0, bottom = SnapGrid.rows - 1
        XCTAssertEqual(SnapGrid.frame(spanning: GridCell(column: 0, row: top), GridCell(column: 2, row: bottom), in: screen),
                       frame(.leftHalf))
        XCTAssertEqual(SnapGrid.frame(spanning: GridCell(column: 3, row: bottom), GridCell(column: 2, row: top), in: screen),
                       frame(.centerThird), "sweeping backwards spans the same cells")
        XCTAssertEqual(SnapGrid.frame(spanning: GridCell(column: 5, row: top), GridCell(column: 0, row: bottom), in: screen),
                       screen)
        XCTAssertEqual(SnapGrid.frame(spanning: GridCell(column: 3, row: top), GridCell(column: 5, row: top), in: screen),
                       frame(.topRight))
        XCTAssertEqual(SnapGrid.frame(spanning: GridCell(column: 2, row: top), GridCell(column: 5, row: bottom), in: screen),
                       frame(.rightTwoThirds))
    }

    func testSingleCellsTileTheScreen() {
        var covered = CGRect.null
        var area: CGFloat = 0
        for column in 0..<SnapGrid.columns {
            for row in 0..<SnapGrid.rows {
                let cell = GridCell(column: column, row: row)
                let cellFrame = SnapGrid.frame(spanning: cell, cell, in: screen)
                covered = covered.union(cellFrame)
                area += cellFrame.width * cellFrame.height
            }
        }
        XCTAssertEqual(covered, screen)
        XCTAssertEqual(area, screen.width * screen.height)
    }

    func testPointsMapToTheCellUnderThemAndClampOutside() {
        let second = SnapGrid.frame(spanning: GridCell(column: 1, row: 1), GridCell(column: 1, row: 1), in: screen)
        XCTAssertEqual(SnapGrid.cell(at: CGPoint(x: second.midX, y: second.midY), in: screen), GridCell(column: 1, row: 1))
        XCTAssertEqual(SnapGrid.cell(at: CGPoint(x: second.minX, y: second.minY), in: screen), GridCell(column: 1, row: 1))
        XCTAssertEqual(SnapGrid.cell(at: CGPoint(x: second.minX - 0.5, y: second.minY - 0.5), in: screen),
                       GridCell(column: 0, row: 0))
        XCTAssertEqual(SnapGrid.cell(at: CGPoint(x: -9999, y: -9999), in: screen), GridCell(column: 0, row: 0))
        XCTAssertEqual(SnapGrid.cell(at: CGPoint(x: 99999, y: 99999), in: screen),
                       GridCell(column: SnapGrid.columns - 1, row: SnapGrid.rows - 1))
    }

    func testRestoreReturnsTheFrameBeforeARunOfSnaps() {
        var memory = SnapMemory<String>()
        let original = CGRect(x: 10, y: 10, width: 500, height: 400)
        memory.recordSnap(of: "mail", from: original, to: frame(.leftHalf), cell: nil)
        memory.recordSnap(of: "mail", from: frame(.leftHalf).offsetBy(dx: 1, dy: 0), to: frame(.maximize), cell: nil)
        XCTAssertEqual(memory.takeOriginal(of: "mail"), original)
        XCTAssertNil(memory.takeOriginal(of: "mail"), "restoring twice has nothing left to restore")
    }

    func testMovingAWindowByHandStartsANewRun() {
        var memory = SnapMemory<String>()
        memory.recordSnap(of: "mail", from: window, to: frame(.leftHalf), cell: nil)
        let draggedAway = CGRect(x: 1700, y: 200, width: 450, height: 320)
        memory.recordSnap(of: "mail", from: draggedAway, to: frame(.rightHalf), cell: nil)
        XCTAssertEqual(memory.takeOriginal(of: "mail"), draggedAway)
    }

    func testMemoryForgetsTheLeastRecentlySnappedWindowAtCapacity() {
        var memory = SnapMemory<Int>(capacity: 2)
        memory.recordSnap(of: 1, from: window, to: screen, cell: nil)
        memory.recordSnap(of: 2, from: window, to: screen, cell: nil)
        memory.recordSnap(of: 1, from: screen, to: frame(.leftHalf), cell: nil)
        memory.recordSnap(of: 3, from: window, to: screen, cell: nil)
        XCTAssertEqual(memory.count, 2)
        XCTAssertNil(memory.takeOriginal(of: 2))
        XCTAssertEqual(memory.takeOriginal(of: 1), window)
        XCTAssertNil(memory.takeOriginal(of: 99))
    }
}
