import SwiftUI

struct RefineView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var currentStroke: [CGPoint] = []
    @State private var isDrawing = false
    @State private var showSaveConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let displayImage = viewModel.displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }

                // Drawing overlay
                Canvas { context, _ in
                    // Show current stroke preview
                    if !currentStroke.isEmpty {
                        let color: Color = viewModel.isRefineAdding ? .red.opacity(0.4) : .blue.opacity(0.4)
                        let brushSize = CGFloat(viewModel.brushSize)
                        for point in currentStroke {
                            let rect = CGRect(
                                x: point.x - brushSize / 2,
                                y: point.y - brushSize / 2,
                                width: brushSize,
                                height: brushSize
                            )
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(color)
                            )
                        }
                    }
                }
                .allowsHitTesting(false)

                // Brush cursor follows finger
                if isDrawing, let lastPoint = currentStroke.last {
                    Circle()
                        .stroke(viewModel.isRefineAdding ? .red : .blue, lineWidth: 1.5)
                        .frame(
                            width: CGFloat(viewModel.brushSize),
                            height: CGFloat(viewModel.brushSize)
                        )
                        .position(lastPoint)
                        .allowsHitTesting(false)
                }

                if viewModel.isProcessing {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDrawing {
                            isDrawing = true
                            currentStroke = []
                        }
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        isDrawing = false
                        let stroke = currentStroke
                        currentStroke = []
                        Task {
                            await viewModel.applyBrushStroke(
                                points: stroke,
                                viewSize: geometry.size
                            )
                        }
                    }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Refine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    if viewModel.canUndoRefine {
                        Button {
                            Task { await viewModel.undoRefine() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let image = viewModel.blurredImage {
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        showSaveConfirmation = true
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .fontWeight(.semibold)
                }
            }

            ToolbarItem(placement: .bottomBar) {
                VStack(spacing: 8) {
                    // Mode toggle
                    HStack(spacing: 16) {
                        Button {
                            viewModel.isRefineAdding = true
                        } label: {
                            Label("Add Blur", systemImage: "plus.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    viewModel.isRefineAdding
                                        ? Color.red.opacity(0.2) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .tint(viewModel.isRefineAdding ? .red : .secondary)

                        Button {
                            viewModel.isRefineAdding = false
                        } label: {
                            Label("Remove Blur", systemImage: "minus.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    !viewModel.isRefineAdding
                                        ? Color.blue.opacity(0.2) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .tint(!viewModel.isRefineAdding ? .blue : .secondary)
                    }

                    // Brush size slider
                    HStack {
                        Circle()
                            .frame(width: 8, height: 8)
                        Slider(value: $viewModel.brushSize, in: 10 ... 80, step: 2)
                        Circle()
                            .frame(width: 24, height: 24)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .alert("Saved", isPresented: $showSaveConfirmation) {
            Button("OK") {}
        } message: {
            Text("Photo saved to your library.")
        }
    }
}
