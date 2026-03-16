import PhotosUI
import SwiftUI

struct HomeView: View {
    @State private var viewModel = EditorViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 72))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))

                    Text("BokeFocus")
                        .font(.largeTitle.bold())

                    Text("Precise background blur")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Select any object, blur the rest")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                }

                Spacer()

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images
                ) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
            .onChange(of: selectedItem) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    await viewModel.loadImage(from: item)
                    showEditor = true
                    selectedItem = nil
                }
            }
            .navigationDestination(isPresented: $showEditor) {
                EditorView(viewModel: viewModel)
            }
        }
    }
}
