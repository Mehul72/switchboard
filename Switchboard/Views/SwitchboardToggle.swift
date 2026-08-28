import SwiftUI

struct SwitchboardToggle: View {
    let isOn: Bool
    let action: (Bool) -> Void

    private let width: CGFloat = 36
    private let height: CGFloat = 20
    private let knob: CGFloat = 16

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Theme.trackOff)
            .frame(width: width, height: height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { action(!isOn) }
    }
}
