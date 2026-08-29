import AppKit
import SwiftUI

enum Theme {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let groupBackground = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let popoverWidth: CGFloat = 400
    static let popoverHeight: CGFloat = 460
    static let edgeInset: CGFloat = 16
}

extension Font {
    static let rowTitle = Font.system(size: 13)
    static let rowSubtitle = Font.system(size: 11)
    static let sectionHeader = Font.system(size: 12, weight: .semibold)
    static let popoverTitle = Font.system(size: 15, weight: .semibold)
    static let footerLabel = Font.system(size: 11)
}

struct Hairline: View {
    var body: some View {
        Theme.separator.frame(height: 1)
    }
}
