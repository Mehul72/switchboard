import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: TweakStore
    @ObservedObject var monitor: SystemMonitor
    let dismiss: () -> Void
    let applyRestarts: () -> Void
    let showShortcuts: () -> Void
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

    private var compactHeight: Bool { height < 420 }
    private let contentTop = "popover-content-top"

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if searchText.isEmpty {
                CategoryNav(selection: $selectedCategory, includesTweakCategories: !compactHeight)
            }
            if !compactHeight, let notice = store.notice {
                NoticeView(notice: notice)
                    .padding(.horizontal, Theme.edgeInset)
                    .padding(.bottom, 10)
            }
            Hairline()
            content
            if !store.pendingRestarts.isEmpty {
                ApplyBar(targets: store.pendingRestarts) {
                    applyRestarts()
                }
            }
        }
        .frame(width: Theme.popoverWidth, height: height)
        .background(PopoverBackground())
        .foregroundStyle(Theme.primary)
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
        .onChange(of: store.search) { _, newValue in
            if searchText != newValue { searchText = newValue }
        }
        .onChange(of: store.category) { _, newValue in
            if selectedCategory != newValue { selectedCategory = newValue }
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
            Image(.brandMark)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text("Switchboard")
                .font(.popoverTitle)
                .foregroundStyle(Theme.primary)
            Spacer()
            settingsMenu
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.top, 4)
        .frame(height: 44)
    }

    private var settingsMenu: some View {
        Menu {
            Button("Keyboard Shortcuts…", action: showShortcuts)
            Divider()
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
            Button("Restore Original Settings") { store.restoreDefaults() }
                .disabled(!store.canRestoreOriginalSettings)
            Divider()
            Button("Quit Switchboard") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switchboard settings")
        .accessibilityLabel("Switchboard settings")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
            TextField("Search all settings", text: $searchText,
                      prompt: Text("Search all settings").foregroundColor(Theme.secondary))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.bodyText)
                .accessibilityLabel("Search all settings")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Button { searchFocused = true } label: {
                Text("⌘F")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 24)
                    .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .accessibilityLabel("Focus search")
            .help("Search all settings (⌘F)")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Theme.fieldBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchFocused ? Theme.accent : Theme.groupBorder,
                              lineWidth: searchFocused ? 1.5 : 1)
        )
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 12)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if compactHeight {
                        if searchText.isEmpty, [.everyday, .files, .capture, .dock].contains(selectedCategory) {
                            TweakCategoryNav(selection: $selectedCategory)
                        }
                        if let notice = store.notice { NoticeView(notice: notice) }
                    }
                    ForEach(store.visibleCategories.filter { $0 != .audio && $0 != .clipboard && $0 != .system }, id: \.self) { category in
                        settingGroup(category)
                    }
                    if shouldShowAudio {
                        audioGroup
                    }
                    if shouldShowClipboard {
                        clipboardGroup
                    }
                    if shouldShowSystem {
                        SystemMonitorView(monitor: monitor)
                    }
                    if store.visible.isEmpty && !shouldShowAudio && !shouldShowClipboard && !shouldShowSystem {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.emptyStateGlyph)
                                .accessibilityHidden(true)
                            Text("No matching settings")
                                .font(.rowTitle)
                                .foregroundStyle(Theme.primary)
                            Text("Try a setting, app name, or category.").font(.rowSubtitle)
                            Button("Clear search") {
                                searchText = ""
                                searchFocused = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    }
                }
                .padding(.horizontal, Theme.edgeInset)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .id(contentTop)
                .background(PopoverScrollStyle())
            }
            .scrollIndicators(.visible)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selectedCategory) { _, _ in proxy.scrollTo(contentTop, anchor: .top) }
            .onChange(of: searchText) { _, _ in proxy.scrollTo(contentTop, anchor: .top) }
        }
        .frame(maxHeight: .infinity)
    }

    private var shouldShowSystem: Bool {
        if searchText.isEmpty { return selectedCategory == .system }
        return ["system", "monitor", "cpu", "gpu", "memory", "swap", "network", "battery", "power", "disk", "thermal"]
            .contains { $0.localizedCaseInsensitiveContains(searchText) }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard")
                    .font(.sectionHeader)
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !store.clips.isEmpty {
                    Button("Clear all") { store.clearClips() }
                        .buttonStyle(.borderless)
                        .font(.rowSubtitle)
                }
            }
            .padding(.horizontal, 4)

            ClipboardHistoryList(store: store)

            Text("Kept in memory only and forgotten when Switchboard quits. Anything a password manager marks as private is skipped.")
                .font(.rowSubtitle)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var audioGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.visibleCategories.count > 1 || !searchText.isEmpty {
                Text(Category.audio.label)
                    .font(.sectionHeader)
                    .foregroundStyle(Theme.primary)
                    .padding(.leading, 4)
            }

            AppVolumeList(store: store)
        }
    }

    private func settingGroup(_ category: Category) -> some View {
        let tweaks = store.tweaks(in: category)
        let quickTools = Set(["everyday.keep-awake", "everyday.region-ocr"])
        let groups = category == .everyday
            ? [tweaks.filter { quickTools.contains($0.id) }, tweaks.filter { !quickTools.contains($0.id) }]
            : [tweaks]
        return VStack(alignment: .leading, spacing: 10) {
            Text(category.label)
                .font(.sectionHeader)
                .foregroundStyle(Theme.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 4)

            ForEach(groups.indices, id: \.self) { index in
                if !groups[index].isEmpty {
                    settingsCard(groups[index])
                }
            }
        }
    }

    private func settingsCard(_ tweaks: [Tweak]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tweaks.enumerated()), id: \.element.id) { index, tweak in
                TweakRow(tweak: tweak, store: store)
                if index < tweaks.count - 1 {
                    Hairline()
                        .padding(.leading, Theme.rowInset + Theme.iconSize + Theme.rowSpacing)
                        .padding(.trailing, Theme.rowInset)
                }
            }
        }
        .groupSurface()
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text(notice.message)
                .font(.rowSubtitle)
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 40)
        .background(colour.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
