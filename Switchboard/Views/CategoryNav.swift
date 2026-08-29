import SwiftUI

struct CategoryNav: View {
    @Binding var selection: Category

    var body: some View {
        Picker("Category", selection: $selection) {
            ForEach(Category.allCases, id: \.self) { category in
                Text(category.label).tag(category)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .padding(.horizontal, Theme.edgeInset)
        .padding(.bottom, 12)
    }
}
