import AppKit
import XCTest

@MainActor
final class AppearanceSettingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "AppearanceSettingTests-\(UUID())"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func setting(applied: @escaping (NSAppearance?) -> Void) -> AppearanceSetting {
        AppearanceSetting(defaults: defaults, applyAppearance: applied)
    }

    func testFirstLaunchFollowsTheSystem() {
        var applied: [NSAppearance?] = []
        let appearance = setting { applied.append($0) }
        XCTAssertEqual(appearance.choice, .system)
        XCTAssertEqual(applied.count, 1)
        XCTAssertNil(applied.last ?? nil)
    }

    func testChoiceAppliesImmediatelyAndSurvivesRelaunch() {
        var applied: [NSAppearance?] = []
        let appearance = setting { applied.append($0) }
        appearance.choice = .dark
        XCTAssertEqual(applied.last??.name, .darkAqua)
        appearance.choice = .light
        XCTAssertEqual(applied.last??.name, .aqua)
        appearance.choice = .system
        XCTAssertNil(applied.last ?? nil, "Match System must hand control back to macOS")
        appearance.choice = .light

        var relaunched: [NSAppearance?] = []
        XCTAssertEqual(setting { relaunched.append($0) }.choice, .light)
        XCTAssertEqual(relaunched.last??.name, .aqua)
    }

    func testOpenWindowsAndThemeColoursFollowTheChoiceLive() throws {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        let appearance = AppearanceSetting(defaults: defaults)
        let shelf = FileShelfController(shelf: FileShelf(),
                                        volumes: ShelfVolumes(load: { $0(.success([])) }, eject: { _, _ in }))
        defer { shelf.close() }
        shelf.show(beside: NSPoint(x: 200, y: 400), incoming: [URL(fileURLWithPath: "/tmp/example")])
        let panel = try XCTUnwrap(shelf.panel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        func canvasHex(in target: NSWindow) -> Int {
            var hex = 0
            target.effectiveAppearance.performAsCurrentDrawingAppearance {
                let colour = NSColor(Theme.canvas).usingColorSpace(.sRGB)!
                hex = Int((colour.redComponent * 255).rounded()) << 16 | Int((colour.greenComponent * 255).rounded()) << 8
                    | Int((colour.blueComponent * 255).rounded())
            }
            return hex
        }
        for (choice, expected, hex) in [(AppearanceChoice.dark, NSAppearance.Name.darkAqua, 0x202226),
                                         (.light, .aqua, 0xF3F5F8), (.dark, .darkAqua, 0x202226)] {
            appearance.choice = choice
            for target in [panel, window] {
                XCTAssertEqual(target.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected, "\(choice)")
                XCTAssertEqual(canvasHex(in: target), hex, "\(choice)")
            }
        }
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("sepia", forKey: AppearanceSetting.defaultsKey)
        XCTAssertEqual(setting { _ in }.choice, .system)
    }
}
