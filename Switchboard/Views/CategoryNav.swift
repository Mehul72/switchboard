import SwiftUI

struct CategoryNav: View {
    @Binding var selection: Category

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Category.allCases, id: \.self) { category in
                        Button { selection = category } label: {
                            Text(category.label)
                                .font(.system(size: 11, weight: selection == category ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(selection == category ? Theme.fieldBackground : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection == category ? .isSelected : [])
                        .id(category)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, category in proxy.scrollTo(category) }
            .onAppear { proxy.scrollTo(selection) }
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 12)
    }
}
