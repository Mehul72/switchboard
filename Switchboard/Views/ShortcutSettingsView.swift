import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    private let shortcuts: GlobalShortcuts
    private var keyMonitor: Any?
    private var errorObservation: AnyCancellable?

    init(shortcuts: GlobalShortcuts) {
        self.shortcuts = shortcuts
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 530),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Keyboard Shortcuts"
        window.minSize = NSSize(width: 560, height: 440)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = NSHostingView(rootView: ShortcutSettingsView(shortcuts: shortcuts) { [weak window] in
            window?.performClose(nil)
        })
        // The scroll view has no intrinsic height; AppKit owns the window's size.
        content.sizingOptions = []
        content.frame = window.contentLayoutRect
        content.autoresizingMask = [.width, .height]
        window.contentView = content
        window.center()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        errorObservation = shortcuts.$errors.removeDuplicates().sink { [weak window] errors in
            guard let window, window.isKeyWindow,
                  let message = ShortcutAction.allCases.compactMap({ errors[$0] }).first else { return }
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: message,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    required init?(coder: NSCoder) { nil }

    func open() {
        shortcuts.cancelRecording()
        shortcuts.retryUnavailable()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) { shortcuts.cancelRecording() }
    func windowWillClose(_ notification: Notification) { shortcuts.cancelRecording() }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        guard window?.isKeyWindow == true, event.window === window,
              shortcuts.recordingAction != nil else { return event }
        guard !event.isARepeat else { return nil }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == kVK_Escape, flags.isEmpty {
            shortcuts.cancelRecording()
        } else if event.keyCode == kVK_Tab, flags.subtracting(.shift).isEmpty {
            shortcuts.cancelRecording()
            return event
        } else if event.keyCode == kVK_Delete, flags.isEmpty {
            shortcuts.record(nil)
        } else {
            shortcuts.record(GlobalShortcut(event: event))
        }
        return nil
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var shortcuts: GlobalShortcuts
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your shortcuts, in every app")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Click a shortcut and press a new combination. Include Control or Option, or Command with another modifier.")
                    .foregroundStyle(Theme.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ShortcutAction.Group.allCases, id: \.self) { group in
                        section(group)
                    }
                }
            }
            Text(shortcuts.recordingAction == nil
                 ? "Shortcuts work while Switchboard is running. Window snapping and switching need Accessibility. Screen Recording enables text capture and window previews."
                 : "Press Escape to cancel, Delete to disable, or Tab to leave the recorder.")
                .font(.rowSubtitle)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if shortcuts.recordingAction != nil {
                    Button("Cancel Recording") { shortcuts.cancelRecording() }
                } else if !shortcuts.errors.isEmpty {
                    Button("Retry Unavailable Shortcuts") { shortcuts.retryUnavailable() }
                }
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .font(.bodyText)
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            if shortcuts.recordingAction != nil { shortcuts.cancelRecording() }
            else { close() }
        }
    }

    private func section(_ group: ShortcutAction.Group) -> some View {
        let actions = ShortcutAction.allCases.filter { $0.group == group }
        return VStack(alignment: .leading, spacing: 6) {
            Text(group.title)
                .font(.rowTitle)
                .foregroundStyle(Theme.secondary)
                .accessibilityAddTraits(.isHeader)
            // Bindings can be edited while snapping is off; say why they do nothing yet.
            if group == .windows, !shortcuts.windowActionsEnabled {
                Text("Switch on “Snap windows” in Everyday to use these.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if group == .windowSwitcher {
                Text(shortcuts.switcherActionsEnabled
                     ? "Command-Tab can replace the macOS switcher here. Hold the shortcut's modifier to browse, then release it to switch."
                     : "Switch on “Window switcher” in Everyday to replace Command-Tab with window previews.")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(actions) { action in
                    shortcutRow(action)
                    if action != actions.last { Hairline() }
                }
            }
            .groupSurface()
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title).font(.rowTitle)
                    if let detail = action.detail {
                        Text(detail)
                            .font(.rowSubtitle)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    shortcuts.beginRecording(action)
                } label: {
                    Text(shortcuts.recordingAction == action
                         ? "Press shortcut…" : shortcuts.bindings[action]?.label ?? "Record Shortcut")
                        .monospaced()
                        .frame(minWidth: 132, minHeight: 24)
                }
                .accessibilityLabel("Shortcut for \(action.title)")
                .accessibilityValue(shortcuts.recordingAction == action
                                    ? "Recording" : shortcuts.bindings[action]?.spokenLabel ?? "Disabled")
                .accessibilityHint(shortcuts.errors[action] ?? "Press to record a new shortcut.")
                Menu {
                    Button("Restore Default") {
                        shortcuts.cancelRecording()
                        shortcuts.set(action.defaultShortcut, for: action)
                    }
                    Button("Disable Shortcut") {
                        shortcuts.cancelRecording()
                        shortcuts.set(nil, for: action)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Options for \(action.title)")
            }
            if let error = shortcuts.errors[action] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.rowSubtitle)
                    .foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }
}
