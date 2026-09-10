import AppKit
import SwiftUI

enum Theme {
    // Opaque colors keep contrast stable regardless of the window behind the panel.
    static let canvas = adaptive(light: 0xF3F5F8, dark: 0x202226)
    static let primary = adaptive(light: 0x20242C, dark: 0xF4F6FA)
    static let secondary = adaptive(light: 0x535D6D, dark: 0xC0C7D2,
                                    highContrastLight: 0x303947, highContrastDark: 0xE3E8F0)
    static let tertiary = adaptive(light: 0x606B79, dark: 0xACB5C3,
                                   highContrastLight: 0x303947, highContrastDark: 0xE3E8F0)
    static let separator = adaptive(light: 0xDDE1E7, dark: 0x444A55)
    static let groupBackground = adaptive(light: 0xFFFFFF, dark: 0x2B2E34)
    static let groupBorder = adaptive(light: 0xD8DDE5, dark: 0x474E5A)
    static let fieldBackground = adaptive(light: 0xFFFFFF, dark: 0x292C32)
    static let controlBackground = adaptive(light: 0xE7ECF3, dark: 0x353A43)
    static let accent = adaptive(light: 0x005BC4, dark: 0x8ABFFF)
    static let selectionBackground = adaptive(light: 0xFFFFFF, dark: 0x484E58)
    static let selectionForeground = primary

    static let popoverWidth: CGFloat = 440
    static let popoverHeight: CGFloat = 560
    static let edgeInset: CGFloat = 16
    static let rowInset: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let iconSize: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let controlColumn: CGFloat = 118

    private static func adaptive(light: UInt32, dark: UInt32,
                                 highContrastLight: UInt32? = nil,
                                 highContrastDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex: UInt32
            switch appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua,
                                                .accessibilityHighContrastAqua,
                                                .darkAqua, .aqua]) {
            case .darkAqua: hex = dark
            case .accessibilityHighContrastAqua: hex = highContrastLight ?? light
            case .accessibilityHighContrastDarkAqua: hex = highContrastDark ?? dark
            default: hex = light
            }
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension Font {
    static let rowTitle = Font.callout
    static let rowSubtitle = Font.system(size: NSFont.smallSystemFontSize)
    static let sectionHeader = Font.system(size: NSFont.smallSystemFontSize, weight: .semibold)
    static let popoverTitle = Font.headline
    static let footerLabel = rowSubtitle
    static let bodyText = Font.callout
    static let emptyStateGlyph = Font.system(size: 22, weight: .regular)
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
            .font(.system(size: 15, weight: .regular))
            .symbolRenderingMode(.monochrome)
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
            .background(hovering ? Theme.controlBackground : .clear)
            .onHover { hovering = $0 }
    }
}
