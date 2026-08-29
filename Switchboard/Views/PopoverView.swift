import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: TweakStore
    let dismiss: () -> Void
    let height: CGFloat

    @State private var launchAtLoginState = LaunchAtLogin.state
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            if store.search.isEmpty {
                CategoryNav(selection: $store.category)
            }
            if let notice = store.notice {
                NoticeView(notice: notice)
                    .padding(.horizontal, Theme.edgeInset)
                    .padding(.bottom, 10)
            }
            content
            if !store.pendingRestarts.isEmpty {
                ApplyBar(targets: store.pendingRestarts) {
                    store.applyPendingRestarts()
                }
            }
            Hairline()
            footer
        }
        .frame(width: Theme.popoverWidth, height: height)
        .background(VisualEffectBackground())
        .onExitCommand {
            if store.search.isEmpty {
                dismiss()
            } else {
                store.search = ""
            }
        }
        .onAppear {
            launchAtLoginState = LaunchAtLogin.state
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "switch.2")
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
                if launchAtLoginState == .requiresApproval {
                    LaunchAtLogin.openSettings()
                } else {
                    updateLaunchAtLogin(launchAtLoginState != .enabled)
                }
            }
            .disabled(launchAtLoginState == .unavailable)
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
        TextField("Search settings", text: $store.search)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .font(.system(size: 12))
            .padding(.horizontal, Theme.edgeInset)
            .padding(.bottom, 10)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(store.visibleCategories, id: \.self) { category in
                    settingGroup(category)
                }
                if store.visible.isEmpty {
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

    private func settingGroup(_ category: Category) -> some View {
        let tweaks = store.tweaks(in: category)
        return VStack(alignment: .leading, spacing: 6) {
            Label(category.label, systemImage: category.symbol)
                .font(.sectionHeader)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(tweaks.enumerated()), id: \.element.id) { index, tweak in
                    TweakRow(tweak: tweak, store: store)
                    if index < tweaks.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .background(Theme.groupBackground, in: RoundedRectangle(cornerRadius: 10))
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
            Text("macOS 14+")
                .font(.footerLabel)
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: 40)
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

    private var launchAtLoginTitle: String {
        switch launchAtLoginState {
        case .enabled: return "Disable Launch at Login"
        case .disabled: return "Launch at Login"
        case .requiresApproval: return "Approve Launch at Login…"
        case .unavailable: return "Launch at Login Unavailable"
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
