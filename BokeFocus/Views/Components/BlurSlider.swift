import SwiftUI

struct BlurSlider: View {
    @Binding var radius: Float
    var onChanged: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "circle")
                .font(.caption)
            Slider(value: $radius, in: 1 ... 100, step: 1) {
                Text(L.blur)
            } onEditingChanged: { editing in
                if !editing {
                    onChanged()
                }
            }
            Image(systemName: "circle.fill")
        }
        .padding(.horizontal)
    }
}
