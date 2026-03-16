import SwiftUI

struct ModeToggle: View {
    @Binding var isNegative: Bool

    var body: some View {
        Toggle(isOn: $isNegative) {
            Label(
                isNegative ? "Exclude" : "Include",
                systemImage: isNegative ? "minus.circle.fill" : "plus.circle.fill"
            )
            .font(.caption)
        }
        .toggleStyle(.button)
        .tint(isNegative ? .red : .green)
    }
}
