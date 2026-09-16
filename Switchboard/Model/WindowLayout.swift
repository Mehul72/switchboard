import CoreGraphics

enum WindowPlacement: CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center

    /// Where this placement sits on the arrow-key map, if it is on it.
    var cell: LayoutCell? {
        switch self {
        case .leftHalf: return LayoutCell(.leftHalf, .full)
        case .rightHalf: return LayoutCell(.rightHalf, .full)
        case .topHalf: return LayoutCell(.full, .top)
        case .bottomHalf: return LayoutCell(.full, .bottom)
        case .topLeft: return LayoutCell(.leftHalf, .top)
        case .topRight: return LayoutCell(.rightHalf, .top)
        case .bottomLeft: return LayoutCell(.leftHalf, .bottom)
        case .bottomRight: return LayoutCell(.rightHalf, .bottom)
        case .leftThird: return LayoutCell(.leftThird, .full)
        case .centerThird: return LayoutCell(.centerThird, .full)
        case .rightThird: return LayoutCell(.rightThird, .full)
        case .maximize: return LayoutCell(.full, .full)
        case .leftTwoThirds, .rightTwoThirds, .center: return nil
        }
    }
}

enum StepDirection: Equatable {
    case left, right, up, down
}

enum WindowCommand: Equatable {
    case place(WindowPlacement)
    case step(StepDirection)
    case nextDisplay
    case previousDisplay
    case restore
}

/// One layout on the arrow-key map: a column span crossed with a row span.
struct LayoutCell: Hashable {
    enum Columns: CaseIterable {
        case leftThird, leftHalf, centerThird, full, rightHalf, rightThird
    }

    enum Rows: CaseIterable {
        case top, full, bottom
    }

    let columns: Columns
    let rows: Rows

    init(_ columns: Columns, _ rows: Rows) {
        self.columns = columns
        self.rows = rows
    }

    static var all: [LayoutCell] {
        Columns.allCases.flatMap { columns in Rows.allCases.map { LayoutCell(columns, $0) } }
    }

    /// Left walks full > left half > left third, and a right-hand layout walks
    /// back towards full; the thirds walk among themselves. Up is the way
    /// out of any layout: thirds never pass through full screen sideways, so
    /// Up goes straight there, and from full screen gives the top half.
    /// Down joins a top half back to full height, then halves it downwards.
    /// Nil means the window is at the map's edge.
    func stepped(_ direction: StepDirection) -> LayoutCell? {
        switch direction {
        case .left: return Self.columnStepLeft[columns].map { LayoutCell($0, rows) }
        case .right: return Self.columnStepRight[columns].map { LayoutCell($0, rows) }
        case .up: return self == Self.fullScreen ? LayoutCell(.full, .top) : Self.fullScreen
        case .down: return Self.rowStepDown[rows].map { LayoutCell(columns, $0) }
        }
    }

    static let fullScreen = LayoutCell(.full, .full)

    /// Where a window that is on no layout starts.
    static func starting(_ direction: StepDirection) -> LayoutCell {
        switch direction {
        case .left: return LayoutCell(.leftHalf, .full)
        case .right: return LayoutCell(.rightHalf, .full)
        case .up: return fullScreen
        case .down: return LayoutCell(.full, .bottom)
        }
    }

    private static let columnStepLeft: [Columns: Columns] = [
        .full: .leftHalf, .leftHalf: .leftThird,
        .rightHalf: .full, .rightThird: .centerThird, .centerThird: .leftThird
    ]
    private static let columnStepRight: [Columns: Columns] = [
        .full: .rightHalf, .rightHalf: .rightThird,
        .leftHalf: .full, .leftThird: .centerThird, .centerThird: .rightThird
    ]
    private static let rowStepDown: [Rows: Rows] = [.top: .full, .full: .bottom]
}

/// Frame arithmetic for snapping, kept free of Accessibility so it can be
/// tested. Every rectangle uses Accessibility coordinates: the origin is the
/// top-left of the primary display and y grows downwards.
enum WindowLayout {
    static func frame(for placement: WindowPlacement, window: CGRect, in screen: CGRect) -> CGRect {
        switch placement {
        case .leftTwoThirds: return columns(screen, from: 0, to: sixths(4, of: screen.width))
        case .rightTwoThirds: return columns(screen, from: sixths(2, of: screen.width), to: screen.width)
        case .center:
            let width = min(window.width, screen.width)
            let height = min(window.height, screen.height)
            return CGRect(x: (screen.midX - width / 2).rounded(.down),
                          y: (screen.midY - height / 2).rounded(.down),
                          width: width, height: height)
        default:
            // Every remaining placement is a cell on the arrow-key map.
            return placement.cell.map { frame(for: $0, in: screen) } ?? screen
        }
    }

    static func frame(for cell: LayoutCell, in screen: CGRect) -> CGRect {
        let width = screen.width
        let horizontal: (start: CGFloat, end: CGFloat)
        switch cell.columns {
        case .leftThird: horizontal = (0, sixths(2, of: width))
        case .leftHalf: horizontal = (0, sixths(3, of: width))
        case .centerThird: horizontal = (sixths(2, of: width), sixths(4, of: width))
        case .full: horizontal = (0, width)
        case .rightHalf: horizontal = (sixths(3, of: width), width)
        case .rightThird: horizontal = (sixths(4, of: width), width)
        }
        let halfHeight = (screen.height / 2).rounded(.down)
        let vertical: (start: CGFloat, end: CGFloat)
        switch cell.rows {
        case .top: vertical = (0, halfHeight)
        case .full: vertical = (0, screen.height)
        case .bottom: vertical = (halfHeight, screen.height)
        }
        return CGRect(x: screen.minX + horizontal.start, y: screen.minY + vertical.start,
                      width: horizontal.end - horizontal.start, height: vertical.end - vertical.start)
    }

    /// The layout a window already fills, so the next arrow press moves on
    /// from it instead of starting over.
    static func cell(matching window: CGRect, in screen: CGRect) -> LayoutCell? {
        LayoutCell.all.first { isClose(frame(for: $0, in: screen), window) }
    }

    /// Thirds and halves are both whole numbers of sixths, and rounding every
    /// boundary the same way is what makes neighbouring layouts meet exactly.
    static func sixths(_ count: Int, of length: CGFloat) -> CGFloat {
        count >= 6 ? length : (length * CGFloat(count) / 6).rounded(.down)
    }

    /// Apps round frames to their own grid, so an untouched window can read
    /// back a point or two away from the frame it was given.
    static func isClose(_ first: CGRect, _ second: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(first.minX - second.minX) <= tolerance && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance && abs(first.height - second.height) <= tolerance
    }

    /// Where a placement or display move sends a window, and the display the
    /// new frame belongs to. Stepping and restoring depend on memory, not only
    /// geometry, so they have no destination here; neither does a move with
    /// only one display.
    static func destination(of command: WindowCommand, window: CGRect,
                            screens: [CGRect]) -> (frame: CGRect, screen: CGRect)? {
        guard let index = screenIndex(for: window, among: screens) else { return nil }
        switch command {
        case .place(let placement):
            return (frame(for: placement, window: window, in: screens[index]), screens[index])
        case .nextDisplay, .previousDisplay:
            guard let target = neighbourIndex(of: index, among: screens,
                                              forward: command == .nextDisplay) else { return nil }
            return (frame(movedFrom: screens[index], to: screens[target], window: window), screens[target])
        case .step, .restore:
            return nil
        }
    }

    /// Scales position and size together, so a window snapped to the left
    /// half of one display lands on the left half of the next.
    static func frame(movedFrom source: CGRect, to target: CGRect, window: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return fitted(window, in: target) }
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let moved = CGRect(x: (target.minX + (window.minX - source.minX) * scaleX).rounded(),
                           y: (target.minY + (window.minY - source.minY) * scaleY).rounded(),
                           width: (window.width * scaleX).rounded(),
                           height: (window.height * scaleY).rounded())
        return fitted(moved, in: target)
    }

    /// A window that cannot be resized keeps its size and hugs the screen
    /// edges its placement touches, so "right half" still means the right edge.
    static func anchored(_ size: CGSize, within requested: CGRect, on screen: CGRect) -> CGRect {
        func origin(start: CGFloat, end: CGFloat, length: CGFloat,
                    screenStart: CGFloat, screenEnd: CGFloat) -> CGFloat {
            if start <= screenStart { return start }
            if end >= screenEnd { return end - length }
            return (start + (end - start - length) / 2).rounded(.down)
        }
        let frame = CGRect(x: origin(start: requested.minX, end: requested.maxX, length: size.width,
                                     screenStart: screen.minX, screenEnd: screen.maxX),
                           y: origin(start: requested.minY, end: requested.maxY, length: size.height,
                                     screenStart: screen.minY, screenEnd: screen.maxY),
                           width: size.width, height: size.height)
        return fitted(frame, in: screen)
    }

    /// Apps enforce minimum sizes, so the frame that comes back can be larger
    /// than the one asked for. Sliding it back keeps a right-half window on
    /// the right edge instead of hanging off the screen.
    static func fitted(_ window: CGRect, in screen: CGRect) -> CGRect {
        let x = max(screen.minX, min(window.minX, screen.maxX - window.width))
        let y = max(screen.minY, min(window.minY, screen.maxY - window.height))
        return CGRect(x: x, y: y, width: window.width, height: window.height)
    }

    /// The display holding most of the window. A window entirely off screen
    /// goes to the display nearest its centre.
    static func screenIndex(for window: CGRect, among screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 {
            return best
        }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.indices.min { distance(from: center, to: screens[$0]) < distance(from: center, to: screens[$1]) }
    }

    /// Displays are cycled left to right, then top to bottom, which matches
    /// their arrangement in System Settings rather than NSScreen's order.
    static func neighbourIndex(of index: Int, among screens: [CGRect], forward: Bool) -> Int? {
        guard screens.count > 1, screens.indices.contains(index) else { return nil }
        let ordered = screens.indices.sorted {
            (screens[$0].minX, screens[$0].minY) < (screens[$1].minX, screens[$1].minY)
        }
        guard let position = ordered.firstIndex(of: index) else { return nil }
        let step = forward ? 1 : ordered.count - 1
        return ordered[(position + step) % ordered.count]
    }

    /// AppKit measures from the bottom-left of the primary display, which is
    /// the first screen and the one whose height anchors both systems.
    static func accessibilityRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func columns(_ screen: CGRect, from start: CGFloat, to end: CGFloat) -> CGRect {
        CGRect(x: screen.minX + start, y: screen.minY, width: end - start, height: screen.height)
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The grid shown while dragging with Control. Six columns, so a sweep over
/// three cells is a half and over two is a third, matching the arrow layouts.
struct GridCell: Equatable {
    let column: Int
    let row: Int
}

enum SnapGrid {
    static let columns = 6
    static let rows = 2

    /// Points outside the screen clamp to its nearest cell, because the
    /// pointer can sit on the menu bar or Dock while the grid is showing.
    static func cell(at point: CGPoint, in screen: CGRect) -> GridCell {
        GridCell(column: index(of: point.x - screen.minX, count: columns, length: screen.width),
                 row: index(of: point.y - screen.minY, count: rows, length: screen.height))
    }

    static func frame(spanning first: GridCell, _ second: GridCell, in screen: CGRect) -> CGRect {
        let columnRange = min(first.column, second.column)...max(first.column, second.column)
        let rowRange = min(first.row, second.row)...max(first.row, second.row)
        let left = boundary(columnRange.lowerBound, count: columns, length: screen.width)
        let right = boundary(columnRange.upperBound + 1, count: columns, length: screen.width)
        let top = boundary(rowRange.lowerBound, count: rows, length: screen.height)
        let bottom = boundary(rowRange.upperBound + 1, count: rows, length: screen.height)
        return CGRect(x: screen.minX + left, y: screen.minY + top, width: right - left, height: bottom - top)
    }

    private static func boundary(_ line: Int, count: Int, length: CGFloat) -> CGFloat {
        line >= count ? length : (length * CGFloat(max(0, line)) / CGFloat(count)).rounded(.down)
    }

    private static func index(of offset: CGFloat, count: Int, length: CGFloat) -> Int {
        let last = (0..<count).last { boundary($0, count: count, length: length) <= offset } ?? 0
        return min(max(last, 0), count - 1)
    }
}

/// Remembers where a window was before the first of a run of snaps, so
/// restoring after left half then maximise returns to the user's own size
/// rather than to the left half.
struct SnapMemory<Window: Hashable> {
    private struct Entry {
        let original: CGRect
        var applied: CGRect
        var cell: LayoutCell?
    }

    private var entries: [Window: Entry] = [:]
    private var order: [Window] = []
    let capacity: Int
    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    var count: Int { entries.count }

    mutating func recordSnap(of window: Window, from current: CGRect, to applied: CGRect, cell: LayoutCell?) {
        if var entry = entries[window], WindowLayout.isClose(entry.applied, current) {
            entry.applied = applied
            entry.cell = cell
            entries[window] = entry
        } else {
            // A window moved by hand since its last snap starts a new run.
            entries[window] = Entry(original: current, applied: applied, cell: cell)
        }
        order.removeAll { $0 == window }
        order.append(window)
        while order.count > capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func takeOriginal(of window: Window) -> CGRect? {
        order.removeAll { $0 == window }
        return entries.removeValue(forKey: window)?.original
    }

    /// The layout of the last snap, while the window still sits where that
    /// snap put it. Apps that round sizes to a character grid never match a
    /// layout frame exactly, so this is what lets them keep stepping.
    func cell(of window: Window, at current: CGRect) -> LayoutCell? {
        guard let entry = entries[window], WindowLayout.isClose(entry.applied, current) else { return nil }
        return entry.cell
    }
}
