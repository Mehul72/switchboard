import SwiftUI

struct CategoryNav: View {
    @Binding var selection: Category
    var includesTweakCategories = true
    @AppStorage("LastTweakCategory") private var lastTweakCategory = Category.everyday.rawValue

    private static let tweakCategories: [Category] = [.everyday, .files, .capture, .dock]

    private var showingTweaks: Bool { Self.tweakCategories.contains(selection) }

    private var section: Binding<String> {
        Binding(
            get: { showingTweaks ? "Tweaks" : selection.label },
            set: { title in
                if title == "Tweaks" {
                    let remembered = Category(rawValue: lastTweakCategory) ?? .everyday
                    selection = Self.tweakCategories.contains(remembered) ? remembered : .everyday
                } else if let category = Category(rawValue: title.lowercased()) {
                    selection = category
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            NavigationStrip(options: ["Tweaks", "Audio", "Clipboard", "System"],
                            selection: section, label: "Sections", enclosed: true)
            if showingTweaks && includesTweakCategories {
                TweakCategoryNav(selection: $selection)
            }
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 16)
        .onAppear { rememberTweakCategory() }
        .onChange(of: selection) { _, _ in rememberTweakCategory() }
    }

    private func rememberTweakCategory() {
        if showingTweaks { lastTweakCategory = selection.rawValue }
    }
}

struct TweakCategoryNav: View {
    @Binding var selection: Category

    var body: some View {
        NavigationStrip(options: [Category.everyday, .files, .capture, .dock].map(\.label),
                        selection: Binding(
                            get: { selection.label },
                            set: { title in
                                if let category = Category(rawValue: title.lowercased()) {
                                    selection = category
                                }
                            }
                        ), label: "Tweak categories", enclosed: false)
    }
}

private struct NavigationStrip: View {
    let options: [String]
    @Binding var selection: String
    let label: String
    let enclosed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focusedOption: String?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option)
                        .font(.system(size: enclosed ? 13 : 12,
                                      weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? Color.accentColor : Theme.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: enclosed ? 30 : 26)
                        .background(selection == option ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.accentColor.opacity(contrast == .increased ? 1 : 0.2))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .focused($focusedOption, equals: option)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .padding(enclosed ? 3 : 0)
        .background(enclosed ? Theme.fieldBackground : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay {
            if enclosed {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(contrast == .increased ? Theme.secondary : Theme.groupBorder)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .onMoveCommand { direction in
            guard let index = options.firstIndex(of: focusedOption ?? selection) else { return }
            let next: Int
            switch direction {
            case .left: next = max(0, index - 1)
            case .right: next = min(options.count - 1, index + 1)
            default: return
            }
            selection = options[next]
            focusedOption = options[next]
        }
    }
}
