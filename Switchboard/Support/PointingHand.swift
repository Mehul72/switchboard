import AppKit
import SwiftUI

extension View {
    /// Nothing in the popover looks like an AppKit control, so the cursor is
    /// the only affordance saying a thing is clickable.
    func pointingHand() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
