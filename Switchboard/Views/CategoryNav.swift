import SwiftUI

private struct TabFrames: PreferenceKey {
    static var defaultValue: [Category: CGRect] = [:]
    static func reduce(value: inout [Category: CGRect], nextValue: () -> [Category: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct CategoryNav: View {
    @Binding var selection: Category

    @State private var frames: [Category: CGRect] = [:]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Category.allCases, id: \.self) { category in
                Text(category.label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primary)
                    .opacity(selection == category ? 1 : 0.35)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: TabFrames.self,
                                                   value: [category: proxy.frame(in: .named("nav"))])
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selection = category
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .coordinateSpace(name: "nav")
        .onPreferenceChange(TabFrames.self) { frames = $0 }
        .overlay(alignment: .bottomLeading) { underline }
    }

    @ViewBuilder
    private var underline: some View {
        if let frame = frames[selection] {
            Theme.accent
                .frame(width: frame.width, height: 2)
                .offset(x: frame.minX)
        }
    }
}
