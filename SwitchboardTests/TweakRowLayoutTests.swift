import AppKit
import SwiftUI
import XCTest

/// Every control in a settings row ends on the same edge. A menu or picker is
/// only as wide as its label, so one extra frame around it is enough to float
/// it in the middle of the control column.
@MainActor
final class TweakRowLayoutTests: XCTestCase {
    private let rowWidth: CGFloat = 408
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard.withUniqueName()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        pasteboard = nil
        try await super.tearDown()
    }

    func testEveryRowsControlEndsOnTheTrailingEdge() throws {
        let store = TweakStore(catalog: TweakCatalog.all, defaults: InMemoryDefaults(), pasteboard: pasteboard,
                               screenText: FakeScreen().source)
        let expectedEdge = rowWidth - Theme.rowInset

        for tweak in TweakCatalog.all {
            let edge = try trailingEdgeOfDrawing(TweakRow(tweak: tweak, store: store))
            // Bezels draw a point or so inside their frame. The bug moved them thirty.
            XCTAssertEqual(edge, expectedEdge, accuracy: 3, "\(tweak.id) control is off the trailing edge")
        }
    }

    /// The rightmost thing a row draws is its control: the row ends in padding.
    private func trailingEdgeOfDrawing(_ row: some View) throws -> CGFloat {
        let host = NSHostingView(rootView: row.frame(width: rowWidth).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: rowWidth, height: 90),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let pointsPerPixel = host.bounds.width / CGFloat(bitmap.pixelsWide)
        for column in stride(from: bitmap.pixelsWide - 1, through: 0, by: -1) {
            // A low bar: an unpressed bezel is drawn as a faint tint, far from opaque.
            for line in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: column, y: line)?.alphaComponent ?? 0) > 0.03 {
                return CGFloat(column + 1) * pointsPerPixel
            }
        }
        return 0
    }
}
