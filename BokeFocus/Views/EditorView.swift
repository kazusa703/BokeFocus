import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var showResult = false
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var dragEnd: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let displayImage = viewModel.displayImage {
                    // Main image
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    // Mask overlay (dim non-selected areas)
                    if let maskOverlay = viewModel.maskOverlayImage,
                       viewModel.editorState == .masked
                    {
                        MaskOverlayView(maskImage: maskOverlay, opacity: 0.5)
                    }

                    // Selection overlay (BBox + points)
                    SelectionOverlayView(
                        points: viewModel.additionalPoints,
                        bboxStart: isDragging ? dragStart : viewModel.bboxStart,
                        bboxEnd: isDragging ? dragEnd : viewModel.bboxEnd,
                        isDragging: isDragging
                    )
                }

                // Processing overlay
                if viewModel.isProcessing {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .transition(.opacity)
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("Analyzing...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .transition(.opacity)
                }

                // State-dependent instruction
                instructionOverlay
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if !isDragging {
                            dragStart = value.startLocation
                            isDragging = true
                        }
                        dragEnd = value.location
                    }
                    .onEnded { _ in
                        let start = dragStart
                        let end = dragEnd
                        isDragging = false
                        Task {
                            await viewModel.handleBBox(
                                start: start,
                                end: end,
                                viewSize: geometry.size
                            )
                        }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        Task {
                            await viewModel.handleTap(
                                at: value.location,
                                viewSize: geometry.size
                            )
                        }
                    }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    if viewModel.canUndo {
                        Button {
                            viewModel.undo()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .tint(.white)
                    }

                    if viewModel.hasMask {
                        Button {
                            viewModel.resetSelection()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .tint(.white)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if viewModel.hasMask {
                        ModeToggle(isNegative: $viewModel.isNegativeMode)
                    }

                    if viewModel.blurredImage != nil {
                        Button("Next") {
                            showResult = true
                        }
                        .fontWeight(.semibold)
                    }
                }
            }

            ToolbarItem(placement: .bottomBar) {
                if viewModel.blurredImage != nil {
                    BlurSlider(radius: $viewModel.blurRadius) {
                        Task { await viewModel.reapplyBlur() }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showResult) {
            RefineView(viewModel: viewModel)
        }
    }

    // MARK: - Instruction overlay per state

    @ViewBuilder
    private var instructionOverlay: some View {
        if !viewModel.isProcessing {
            VStack {
                Spacer()
                Group {
                    switch viewModel.editorState {
                    case .idle:
                        HStack(spacing: 8) {
                            Image(systemName: "hand.tap")
                                .foregroundStyle(.yellow)
                            Text("Tap or draw a box to select")
                        }
                    case .masked:
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.green)
                            Text("Tap to refine selection")
                        }
                    case .blurred:
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(.blue)
                            Text("Adjust blur, then tap Next")
                        }
                    case .processing:
                        EmptyView()
                    }
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 100)
                .animation(.easeInOut(duration: 0.3), value: viewModel.editorState)
            }
        }
    }
}
