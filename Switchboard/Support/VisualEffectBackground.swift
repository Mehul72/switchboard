import AppKit
import SwiftUI

struct PopoverBackground: View {
    var body: some View {
        Theme.canvas
    }
}

// The scroll bar style itself comes from PreferenceStore.keepScrollBarsVisible,
// so SwiftUI sizes the content for it; this only tunes the bar's appearance.
struct PopoverScrollStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollAnchor { ScrollAnchor() }

    func updateNSView(_ view: ScrollAnchor, context: Context) {
        view.configureScrollView()
    }

    final class ScrollAnchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureScrollView()
        }

        func configureScrollView() {
            DispatchQueue.main.async { [weak self] in
                guard let scrollView = self?.enclosingScrollView else { return }
                scrollView.hasVerticalScroller = true
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.controlSize = .small
                scrollView.drawsBackground = false
            }
        }
    }
}
