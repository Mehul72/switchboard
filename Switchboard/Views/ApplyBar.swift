import SwiftUI

struct ApplyBar: View {
    let summary: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(summary)
                .font(.footerLabel)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text("Apply")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 5).fill(Theme.trackOff)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Hairline() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
