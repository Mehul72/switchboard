import AppKit
import SwiftUI

private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopoverView: View {
    @ObservedObject var store: TweakStore
    let dismiss: () -> Void

    @State private var contentHeight: CGFloat
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @FocusState private var searchFocused: Bool

    init(store: TweakStore, dismiss: @escaping () -> Void) {
        self.store = store
        self.dismiss = dismiss
        _contentHeight = State(initialValue: Self.rowHeight(for: store.visible))
    }

    // Header, search, navigation and footer occupy 152pt. The Apply bar takes
    // its space from the rows so the popover never grows beyond 520pt.
    private var maxScrollHeight: CGFloat {
        Theme.maxPopoverHeight - 152 - (store.pendingRestarts.isEmpty ? 0 : 36)
    }

    private static func rowHeight(for tweaks: [Tweak]) -> CGFloat {
        tweaks.reduce(8) { height, tweak in
            height + (tweak.subtitle == nil ? 34 : 46)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Hairline()
            CategoryNav(selection: $store.category)
                .opacity(store.search.isEmpty ? 1 : 0.35)
                .disabled(!store.search.isEmpty)
            content
            // Sits above the footer rather than over it, so Quit stays reachable
            // while a restart is pending.
            if !store.pendingRestarts.isEmpty {
                ApplyBar(summary: SystemRestart.summary(for: store.pendingRestarts)) {
                    store.applyPendingRestarts()
                }
            }
            Hairline()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .background(VisualEffectBackground())
        .onExitCommand(perform: dismiss)
        .onAppear { searchFocused = true }
        .animation(.spring(response: 0.2, dampingFraction: 0.85), value: store.pendingRestarts)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Text("Switchboard")
                .font(.popoverTitle)
                .foregroundStyle(Theme.primary)
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: 52)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
            TextField("Search", text: $store.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primary)
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Text("Restore defaults")
                .font(.footerLabel)
                .foregroundStyle(Theme.tertiary)
                .contentShape(Rectangle())
                .onTapGesture { store.restoreDefaults() }
                .opacity(store.hasUndoRecord ? 1 : 0.4)
                .disabled(!store.hasUndoRecord)
                .pointingHand()
            Spacer()
            Text("Quit")
                .font(.footerLabel)
                .foregroundStyle(Theme.tertiary)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.terminate(nil) }
                .pointingHand()
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: 40)
    }

    // MARK: - Rows

    @ViewBuilder
    private var content: some View {
        if store.visible.isEmpty {
            Text("No matches")
                .font(.rowTitle)
                .foregroundStyle(Theme.tertiary)
                .frame(height: 88)
        } else {
            ScrollView {
                rows
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), maxScrollHeight))
            .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
        }
    }

    @ViewBuilder
    private var rows: some View {
        if store.search.isEmpty {
            VStack(spacing: 0) {
                ForEach(store.visible) { TweakRow(tweak: $0, store: store) }
            }
            .padding(.vertical, 4)
            .id(store.category)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: store.category)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Category.allCases, id: \.self) { category in
                    let matches = store.visible.filter { $0.category == category }
                    if !matches.isEmpty {
                        Text(category.label.uppercased())
                            .font(.sectionHeader)
                            .tracking(0.6)
                            .foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, Theme.edgeInset)
                            .padding(.top, 12)
                            .padding(.bottom, 20)
                        ForEach(matches) { TweakRow(tweak: $0, store: store) }
                    }
                }
            }
            .padding(.bottom, 8)
            .id(store.search)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.1), value: store.search)
        }
    }
}
