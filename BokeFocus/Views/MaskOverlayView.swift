import SwiftUI

struct MaskOverlayView: View {
    let maskImage: UIImage
    let opacity: Double

    var body: some View {
        // Invert mask: show dark overlay on non-selected areas
        // Mask from Vision: white=foreground, black=background
        // We want to dim background → invert mask then overlay
        Image(uiImage: maskImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .colorInvert()
            .blendMode(.multiply)
            .opacity(opacity)
            .allowsHitTesting(false)
    }
}
