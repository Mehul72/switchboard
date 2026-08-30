import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: TweakStore
    let dismiss: () -> Void
    let applyRestarts: () -> Void
    let height: CGFloat

    @State private var launchAtLoginState = LaunchAtLogin.state
    // Bound straight to the store, SwiftUI's text-field writeback buffer
    // flushes into the @Published property while the view tree is updating,
    // which is what "Publishing changes from within view updates" reports.
    // Local state absorbs the writeback; the store is updated after the pass.
    @State private var searchText = ""
    // The segmented control writes back through the same buffer as the search
    // field, so it needs the same treatment.
    @State private var selectedCategory: Category = .everyday
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if searchText.isEmpty {
                CategoryNav(selection: $selectedCategory)
            }
            if let notice = store.notice {
                NoticeView(notice: notice)
                    .padding(.horizontal, Theme.edgeInset)
                    .padding(.bottom, 10)
            }
            content
            if !store.pendingRestarts.isEmpty {
                ApplyBar(targets: store.pendingRestarts) {
                    applyRestarts()
                }
            }
            Hairline()
            footer
        }
        .frame(width: Theme.popoverWidth, height: height)
        .background(VisualEffectBackground())
        .translationBridge(store)
        .onExitCommand {
            if searchText.isEmpty {
                dismiss()
            } else {
                searchText = ""
            }
        }
        .onChange(of: searchText) { _, newValue in
            store.search = newValue
        }
        .onChange(of: selectedCategory) { _, newValue in
            store.category = newValue
            if newValue == .audio {
                store.refreshAudioApps()
            }
        }
        .onAppear {
            searchText = store.search
            selectedCategory = store.category
            launchAtLoginState = LaunchAtLogin.state
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Switchboard")
                    .font(.popoverTitle)
                    .foregroundStyle(Theme.primary)
                Text("Useful fixes for everyday macOS friction")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.top, 8)
        .frame(height: 54)
    }

    private var settingsMenu: some View {
        Menu {
            Button(launchAtLoginTitle) {
                if launchAtLoginState == .unavailable {
                    recoverLaunchAtLogin()
                } else if launchAtLoginState == .requiresApproval {
                    LaunchAtLogin.openSettings()
                } else {
                    updateLaunchAtLogin(launchAtLoginState != .enabled)
                }
            }
            Divider()
            Button("Quit Switchboard") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Switchboard settings")
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 12.5))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.4) : Theme.groupBorder,
                              lineWidth: 1)
        )
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 10)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(store.visibleCategories.filter { $0 != .audio && $0 != .clipboard }, id: \.self) { category in
                    settingGroup(category)
                }
                if shouldShowAudio {
                    audioGroup
                }
                if shouldShowClipboard {
                    clipboardGroup
                }
                if store.visible.isEmpty && !shouldShowAudio && !shouldShowClipboard {
                    Text("No matching settings")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }
            }
            .padding(.horizontal, Theme.edgeInset)
            .padding(.bottom, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
    }

    private var shouldShowAudio: Bool {
        if searchText.isEmpty {
            return selectedCategory == .audio
        }
        let terms = ["audio", "volume", "sound", "speaker"] + store.audioApps.map(\.name)
        return terms.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var shouldShowClipboard: Bool {
        if searchText.isEmpty { return selectedCategory == .clipboard }
        let terms = ["clipboard", "history", "clip", "paste", "copied"]
        return terms.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var clipboardGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if store.visibleCategories.count > 1 || !searchText.isEmpty {
                    Text(Category.clipboard.label.uppercased())
                        .font(.sectionHeader)
                        .kerning(0.5)
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer()
                if !store.clips.isEmpty {
                    Button("Clear") { store.clearClips() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                }
            }
            .padding(.horizontal, 4)

            ClipboardHistoryList(store: store)

            Text("Kept in memory only and forgotten when Switchboard quits. Anything a password manager marks as private is skipped.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var audioGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.visibleCategories.count > 1 || !searchText.isEmpty {
                Text(Category.audio.label.uppercased())
                    .font(.sectionHeader)
                    .kerning(0.5)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 4)
            }

            AppVolumeList(store: store)

            Text("The first adjustment asks for System Audio Recording access. Set an app to 100% to return it to the normal system mixer.")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func settingGroup(_ category: Category) -> some View {
        let tweaks = store.tweaks(in: category)
        return VStack(alignment: .leading, spacing: 5) {
            // Only worth naming when a search is showing several at once.
            if store.visibleCategories.count > 1 {
                Text(category.label.uppercased())
                    .font(.sectionHeader)
                    .kerning(0.5)
                    .foregroundStyle(Theme.tertiary)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                ForEach(Array(tweaks.enumerated()), id: \.element.id) { index, tweak in
                    TweakRow(tweak: tweak, store: store)
                    if index < tweaks.count - 1 {
                        Theme.separator
                            .frame(height: 1)
                            .padding(.leading, Theme.rowInset + Theme.iconSize + Theme.rowSpacing)
                    }
                }
            }
            .background(Theme.groupBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Theme.groupBorder, lineWidth: 1)
            )
        }
    }

    private var footer: some View {
        HStack {
            Button("Restore Original Settings") { store.restoreDefaults() }
                .buttonStyle(.plain)
                .font(.footerLabel)
                .foregroundStyle(Theme.secondary)
                .disabled(!store.canRestoreOriginalSettings)
            Spacer()
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: 38)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        switch LaunchAtLogin.set(enabled) {
        case .success(let state):
            launchAtLoginState = state
            switch state {
            case .enabled:
                store.notice = StoreNotice(kind: .success,
                                           message: "Switchboard will launch at login.")
            case .disabled:
                store.notice = StoreNotice(kind: .success,
                                           message: "Launch at login disabled.")
            case .requiresApproval:
                store.notice = StoreNotice(kind: .information,
                                           message: "Allow Switchboard in System Settings > General > Login Items.")
            case .unavailable:
                store.notice = StoreNotice(kind: .error,
                                           message: "Launch at login is unavailable for this copy of Switchboard.")
            }
        case .failure:
            launchAtLoginState = LaunchAtLogin.state
            store.notice = StoreNotice(kind: .error,
                                       message: "macOS could not update Login Items. Try again after moving Switchboard to Applications.")
        }
    }

    private func recoverLaunchAtLogin() {
        LaunchAtLogin.recoverFromUnavailableCopy { result in
            switch result {
            case .relaunched:
                break
            case .needsInstallation:
                store.notice = StoreNotice(
                    kind: .information,
                    message: "Move Switchboard to Applications, then open that copy to enable launch at login."
                )
            case .failed:
                store.notice = StoreNotice(
                    kind: .error,
                    message: "The installed copy could not be opened. Open Switchboard from Applications and try again."
                )
            }
        }
    }

    private var launchAtLoginTitle: String {
        switch launchAtLoginState {
        case .enabled: return "Disable Launch at Login"
        case .disabled: return "Launch at Login"
        case .requiresApproval: return "Approve Launch at Login…"
        case .unavailable: return LaunchAtLogin.recoveryTitle
        }
    }
}

private struct NoticeView: View {
    let notice: StoreNotice

    private var symbol: String {
        switch notice.kind {
        case .success: return "checkmark.circle.fill"
        case .information: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var colour: Color {
        switch notice.kind {
        case .success: return .green
        case .information: return .accentColor
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text(notice.message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(colour.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}
