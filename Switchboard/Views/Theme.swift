import AppKit
import SwiftUI

enum Theme {
    // Desaturated cyan. Pulled down and darkened in light mode so it still
    // reads against a bright popover.
    static let accent = Color(nsColor: NSColor(name: "SwitchboardAccent") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.38, green: 0.78, blue: 0.79, alpha: 1)
            : NSColor(srgbRed: 0.11, green: 0.51, blue: 0.55, alpha: 1)
    })

    static let primary = Color.primary
    static let secondary = Color.primary.opacity(0.55)
    static let tertiary = Color.primary.opacity(0.35)
    static let hairline = Color.primary.opacity(0.06)
    static let hover = Color.primary.opacity(0.05)
    static let trackOff = Color.primary.opacity(0.12)

    static let popoverWidth: CGFloat = 380
    static let maxPopoverHeight: CGFloat = 520
    static let edgeInset: CGFloat = 12
}

extension Font {
    static let rowTitle = Font.system(size: 13)
    static let rowSubtitle = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 10, weight: .semibold)
    static let popoverTitle = Font.system(size: 13, weight: .semibold)
    static let footerLabel = Font.system(size: 11)
}

struct Hairline: View {
    var body: some View {
        Theme.hairline
            .frame(height: 1)
            .padding(.horizontal, Theme.edgeInset)
    }
}
