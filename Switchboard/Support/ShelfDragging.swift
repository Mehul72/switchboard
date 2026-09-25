import AppKit
import SwiftUI

@MainActor
final class ShelfDragState: ObservableObject {
    @Published var urls: [URL] = []
    @Published var isTargeted = false
    var isDraggingOut = false

    func enter(_ urls: [URL]) {
        if self.urls != urls { self.urls = urls }
        if !isTargeted { isTargeted = true }
    }

    func finish() {
        urls = []
        isTargeted = false
    }
}

final class ShelfDropHostingView<Content: View>: NSHostingView<Content> {
    var accepts: ([URL]) -> Bool = { !$0.isEmpty }
    var onHover: ([URL]) -> Void = { _ in }
    var onDrop: ([URL]) -> Bool = { _ in false }
    var onExit: () -> Void = {}
    var onEnd: () -> Void = {}

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = FileShelf.readFiles(from: sender.draggingPasteboard)
        onHover(urls)
        return accepts(urls) && sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) { onExit() }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        accepts(FileShelf.readFiles(from: sender.draggingPasteboard)) && sender.draggingSourceOperationMask.contains(.copy)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = FileShelf.readFiles(from: sender.draggingPasteboard)
        guard accepts(urls), sender.draggingSourceOperationMask.contains(.copy) else { return false }
        let handled = onDrop(urls)
        onEnd()
        return handled
    }

    override func draggingEnded(_ sender: NSDraggingInfo) { onEnd() }
}

struct ShelfDropTarget<Content: View>: NSViewRepresentable {
    let accepts: ([URL]) -> Bool
    let onHover: ([URL]) -> Void
    let onDrop: ([URL]) -> Bool
    let onExit: () -> Void
    let content: Content

    init(accepts: @escaping ([URL]) -> Bool, onHover: @escaping ([URL]) -> Void,
         onDrop: @escaping ([URL]) -> Bool, onExit: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.accepts = accepts
        self.onHover = onHover
        self.onDrop = onDrop
        self.onExit = onExit
        self.content = content()
    }

    func makeNSView(context: Context) -> ShelfDropHostingView<Content> {
        let view = ShelfDropHostingView(rootView: content)
        view.sizingOptions = []
        return view
    }

    func updateNSView(_ view: ShelfDropHostingView<Content>, context: Context) {
        view.rootView = content
        view.accepts = accepts
        view.onHover = onHover
        view.onDrop = onDrop
        view.onExit = onExit
        view.onEnd = onExit
    }
}

struct ShelfDragSource<Content: View>: NSViewRepresentable {
    let resolveURL: () -> URL?
    let onDragging: (Bool) -> Void
    var onClick: () -> Void = {}
    let content: Content

    init(resolveURL: @escaping () -> URL?, onDragging: @escaping (Bool) -> Void,
         onClick: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self.resolveURL = resolveURL
        self.onDragging = onDragging
        self.onClick = onClick
        self.content = content()
    }

    func makeNSView(context: Context) -> ShelfFileDragView<Content> {
        ShelfFileDragView(rootView: content)
    }

    func updateNSView(_ view: ShelfFileDragView<Content>, context: Context) {
        view.rootView = content
        view.resolveURL = resolveURL
        view.onDragging = onDragging
        view.onClick = onClick
    }
}

final class ShelfFileDragView<Content: View>: NSView, NSDraggingSource {
    private let host: NSHostingView<Content>
    var rootView: Content {
        get { host.rootView }
        set { host.rootView = newValue }
    }
    var resolveURL: () -> URL? = { nil }
    var onDragging: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    private var mouseDownPoint: NSPoint?

    init(rootView: Content) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = convert(event.locationInWindow, from: nil) }
    /// A press that never became a drag is a click; a drag clears the point first.
    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        onClick()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        mouseDownPoint = nil
        guard let url = resolveURL() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
        onDragging(true)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // A temporary shelf must never move or delete the user's original file.
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragging(false)
    }
}
