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
        VStack(spacing: 8) {
            NavigationStrip(options: ["Tweaks", "Audio", "Clipboard", "System"],
                            selection: section, label: "Sections", enclosed: true)
            if showingTweaks && includesTweakCategories {
                TweakCategoryNav(selection: $selection)
            }
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 8)
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
    @State private var hoveredOption: String?

    private func symbol(for option: String) -> String {
        switch option {
        case "Tweaks": return "slider.horizontal.3"
        case "Audio": return "speaker.wave.2"
        case "Clipboard": return "doc.on.clipboard"
        default: return "gauge.with.dots.needle.50percent"
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    HStack(spacing: 6) {
                        if enclosed {
                            Image(systemName: symbol(for: option))
                                .font(.system(size: 12))
                                .foregroundStyle(selection == option ? Theme.accent : Theme.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(option)
                            .font(enclosed ? .rowTitle : .rowSubtitle)
                            .fontWeight(selection == option ? .medium : .regular)
                    }
                    .foregroundStyle(selection == option ?
                                     (enclosed ? Theme.selectionForeground : Theme.accent) : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selection == option && enclosed ? Theme.selectionBackground :
                                  hoveredOption == option ? Theme.controlBackground : .clear)
                            .shadow(color: .black.opacity(enclosed && selection == option ? 0.08 : 0),
                                    radius: 2, y: 1)
                    }
                    .overlay(alignment: .bottom) {
                        if !enclosed && selection == option {
                            Capsule().fill(Theme.accent).frame(height: 2)
                                .padding(.horizontal, 16)
                        }
                    }
                    .overlay {
                        if focusedOption == option {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.accent, lineWidth: 2)
                                .padding(-2)
                                .allowsHitTesting(false)
                        } else if enclosed && selection == option {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(contrast == .increased ? Theme.secondary : Theme.groupBorder)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focused($focusedOption, equals: option)
                .onHover { hoveredOption = $0 ? option : nil }
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
