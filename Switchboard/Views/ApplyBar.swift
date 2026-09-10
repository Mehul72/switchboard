import SwiftUI

struct ApplyBar: View {
    let targets: Set<RestartTarget>
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(SystemRestart.requirement(for: targets))
                .font(.rowSubtitle)
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(SystemRestart.summary(for: targets), action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.edgeInset)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(Theme.groupBackground)
        .overlay(alignment: .top) { Hairline() }
    }
}
