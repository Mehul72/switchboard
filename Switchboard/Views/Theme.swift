import AppKit
import SwiftUI

enum Theme {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.6)

    /// Cards sit on a vibrant popover background, so they lift with a very
    /// light tint rather than a solid fill, the way System Settings does.
    static let groupBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)
    static let groupBorder = Color(nsColor: .separatorColor).opacity(0.35)
    static let fieldBackground = Color(nsColor: .textBackgroundColor).opacity(0.5)

    static let popoverWidth: CGFloat = 420
    static let popoverHeight: CGFloat = 500

    /// One spacing scale, so nothing is nudged by eye.
    static let edgeInset: CGFloat = 14
    static let rowInset: CGFloat = 11
    static let rowSpacing: CGFloat = 10
    static let iconSize: CGFloat = 22
    static let cornerRadius: CGFloat = 8
    /// Keeps a control from crowding out the label beside it.
    static let controlColumn: CGFloat = 118
}

extension Font {
    static let rowTitle = Font.system(size: 13)
    static let rowSubtitle = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let popoverTitle = Font.system(size: 14, weight: .semibold)
    static let footerLabel = Font.system(size: 11)
}

struct Hairline: View {
    var body: some View {
        Theme.separator.frame(height: 1)
    }
}

/// The tinted rounded glyph macOS uses to head a settings row.
struct RowIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: Theme.iconSize, height: Theme.iconSize)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 5.5))
            .accessibilityHidden(true)
    }
}
