import SwiftUI
import UIKit

struct ResultView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var showOriginal = false
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let displayImage = showOriginal ? viewModel.originalImage : viewModel.blurredImage {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .accessibilityLabel(showOriginal ? L.original : L.result)
                    .accessibilityHint(L.longPressCompare)
                    .onLongPressGesture(
                        minimumDuration: .infinity,
                        pressing: { pressing in showOriginal = pressing },
                        perform: {}
                    )
                    .overlay(alignment: .bottom) {
                        if showOriginal {
                            Text(L.original)
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.bottom, 12)
                        }
                    }
            }

            Text(L.longPressCompare)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = viewModel.blurredImage {
                HStack(spacing: 16) {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview("BokeFocus", image: Image(uiImage: image))
                    ) {
                        Label(L.share, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding()
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                    }

                    Button {
                        Task { await savePhoto() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView()
                            } else {
                                Label(L.save, systemImage: "square.and.arrow.down")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity).padding()
                        .background(.secondary.opacity(0.2), in: .capsule)
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .navigationTitle(L.result)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L.saved, isPresented: $showSaveSuccess) {
            Button(L.ok) {}
        } message: {
            Text(L.photoSaved)
        }
        .alert(L.error, isPresented: $showSaveError) {
            Button(L.ok) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func savePhoto() async {
        isSaving = true
        let result = await viewModel.saveToPhotoLibrary()
        isSaving = false

        switch result {
        case .success:
            showSaveSuccess = true
            AdManager.shared.showInterstitial()
        case let .failure(message):
            saveErrorMessage = message
            showSaveError = true
        }
    }
}
