import SwiftUI

struct ResultView: View {
    let blurredImage: UIImage?
    let originalImage: UIImage?
    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let displayImage = showOriginal ? originalImage : blurredImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .onLongPressGesture(
                        minimumDuration: .infinity,
                        pressing: { pressing in
                            showOriginal = pressing
                        },
                        perform: {}
                    )
                    .overlay(alignment: .bottom) {
                        if showOriginal {
                            Text("Original")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 12)
                        }
                    }
            }

            Text("Long press to compare")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = blurredImage {
                HStack(spacing: 16) {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview("BokeFocus", image: Image(uiImage: image))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                    }

                    Button {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.secondary.opacity(0.2), in: .capsule)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
    }
}
