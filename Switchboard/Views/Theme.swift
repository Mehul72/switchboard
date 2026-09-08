import AppKit
import SwiftUI

enum Theme {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor).opacity(0.45)

    /// Cards sit on a vibrant popover background, so they lift with a very
    /// light tint rather than a solid fill, the way System Settings does.
    static let groupBackground = Color(nsColor: .controlBackgroundColor).opacity(0.5)
    static let groupBorder = Color(nsColor: .separatorColor).opacity(0.45)
    static let fieldBackground = Color(nsColor: .textBackgroundColor).opacity(0.35)

    static let popoverWidth: CGFloat = 460
    static let popoverHeight: CGFloat = 560

    /// One spacing scale, so nothing is nudged by eye.
    static let edgeInset: CGFloat = 18
    static let rowInset: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let iconSize: CGFloat = 22
    static let cornerRadius: CGFloat = 10
    /// Keeps a control from crowding out the label beside it.
    static let controlColumn: CGFloat = 118
}

extension Font {
    static let rowTitle = Font.system(size: 13)
    static let rowSubtitle = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 11, weight: .semibold)
    static let popoverTitle = Font.system(size: 15, weight: .semibold)
    static let footerLabel = Font.system(size: 11)
    /// Full-size text the user reads or types, rather than a row label.
    static let bodyText = Font.system(size: 13)
    /// The oversized glyph an empty list centres on.
    static let emptyStateGlyph = Font.system(size: 26, weight: .light)
}

struct Hairline: View {
    var body: some View {
        Theme.separator.frame(height: 1)
    }
}

struct RowIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Theme.secondary)
            .frame(width: Theme.iconSize, height: Theme.iconSize)
            .accessibilityHidden(true)
    }
}

extension View {
    func groupSurface() -> some View { modifier(GroupSurface()) }
    func rowHoverHighlight() -> some View { modifier(RowHoverHighlight()) }
}

private struct GroupSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Theme.groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(contrast == .increased ? Theme.secondary : Theme.groupBorder,
                                  lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct RowHoverHighlight: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
            .onHover { hovering = $0 }
    }
}
