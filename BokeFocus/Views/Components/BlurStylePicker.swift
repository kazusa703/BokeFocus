import SwiftUI

struct BlurStylePicker: View {
    @Binding var selected: BlurStyle
    var onChanged: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BlurStyle.allCases) { style in
                Button {
                    if selected != style {
                        selected = style
                        onChanged()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: style.icon)
                            .font(.body)
                        Text(style.label)
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        selected == style
                            ? Color.white.opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .tint(selected == style ? .white : .gray)
            }
        }
        .padding(.horizontal, 4)
    }
}
