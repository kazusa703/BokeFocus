import PhotosUI
import SwiftUI

struct HomeView: View {
    @Environment(LanguageManager.self) private var langManager
    @State private var viewModel = EditorViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var showEditor = false
    @State private var showSettings = false
    @State private var showLanguagePicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 72))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))

                    Text(L.appName)
                        .font(.largeTitle.bold())

                    Text(L.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    HowToRow(icon: "hand.tap", color: .blue, text: L.howToSelect)
                    HowToRow(icon: "plus.circle", color: .green, text: L.howToRefine)
                    HowToRow(icon: "slider.horizontal.3", color: .purple, text: L.howToBlur)
                    HowToRow(icon: "paintbrush.pointed", color: .orange, text: L.howToBrush)
                }
                .padding(.horizontal, 32)

                Spacer()

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images
                ) {
                    Label(L.choosePhoto, systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.tint, in: .capsule)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLanguagePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(langManager.current.displayName)
                                .font(.caption)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .confirmationDialog(L.language, isPresented: $showLanguagePicker) {
                ForEach(AppLanguage.allCases) { lang in
                    Button(lang.displayName) {
                        langManager.current = lang
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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

private struct HowToRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
