import SwiftUI

struct ApplyBar: View {
    let targets: Set<RestartTarget>
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(SystemRestart.requirement(for: targets))
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Button(SystemRestart.summary(for: targets), action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.edgeInset)
        .frame(height: 44)
        .background(.bar)
        .overlay(alignment: .top) { Hairline() }
    }
}
