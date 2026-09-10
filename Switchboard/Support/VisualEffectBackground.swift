import AppKit
import SwiftUI

struct PopoverBackground: View {
    var body: some View {
        Theme.canvas
    }
}

// SwiftUI follows the system's auto-hiding scrollbar preference. This panel
// needs a persistent position cue when its settings extend below the fold.
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
                scrollView.scrollerStyle = .legacy
                scrollView.verticalScroller?.controlSize = .small
                scrollView.drawsBackground = false
            }
        }
    }
}
