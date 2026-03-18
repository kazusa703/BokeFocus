import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var showRefine = false
    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var dragEnd: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let displayImage = viewModel.displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    if let maskOverlay = viewModel.maskOverlayImage,
                       viewModel.editorState == .masked
                    {
                        MaskOverlayView(maskImage: maskOverlay, opacity: 0.5)
                    }

                    SelectionOverlayView(
                        points: viewModel.additionalPoints,
                        bboxStart: isDragging ? dragStart : viewModel.bboxStart,
                        bboxEnd: isDragging ? dragEnd : viewModel.bboxEnd,
                        isDragging: isDragging
                    )
                }

                if viewModel.isProcessing || viewModel.isEncoding {
                    Color.black.opacity(0.3).ignoresSafeArea()
                        .transition(.opacity)
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text(viewModel.isEncoding ? L.analyzing : L.analyzing)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .transition(.opacity)
                }

                instructionOverlay
            }
            .contentShape(Rectangle())
            .gesture(bboxGesture(geometry: geometry))
            .simultaneousGesture(tapGesture(geometry: geometry))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 12) {
                    if viewModel.canUndo {
                        Button { viewModel.undo() } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .tint(.white)
                    }
                    if viewModel.hasMask {
                        Button { viewModel.resetSelection() } label: {
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
                        Button(L.next) { showRefine = true }
                            .fontWeight(.semibold)
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if viewModel.blurredImage != nil {
                    VStack(spacing: 8) {
                        BlurStylePicker(selected: $viewModel.blurStyle) {
                            Task { await viewModel.reapplyBlur() }
                        }
                        BlurSlider(radius: $viewModel.blurRadius) {
                            Task { await viewModel.reapplyBlur() }
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showRefine) {
            RefineView(viewModel: viewModel)
        }
    }

    // MARK: - Gestures (state-aware to avoid conflicts)

    /// BBox drag gesture — only active when no mask exists
    private func bboxGesture(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !viewModel.hasMask else { return }
                if !isDragging {
                    dragStart = value.startLocation
                    isDragging = true
                }
                dragEnd = value.location
            }
            .onEnded { _ in
                guard isDragging else { return }
                let start = dragStart
                let end = dragEnd
                isDragging = false
                Task {
                    await viewModel.handleBBox(
                        start: start, end: end,
                        viewSize: geometry.size
                    )
                }
            }
    }

    /// Tap gesture — always active (auto-detect or point refinement)
    private func tapGesture(geometry: GeometryProxy) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                Task {
                    await viewModel.handleTap(
                        at: value.location,
                        viewSize: geometry.size
                    )
                }
            }
    }

    // MARK: - Instruction overlay

    @ViewBuilder
    private var instructionOverlay: some View {
        if !viewModel.isProcessing, !viewModel.isEncoding {
            VStack {
                Spacer()
                Group {
                    switch viewModel.editorState {
                    case .idle:
                        HStack(spacing: 8) {
                            Image(systemName: "hand.tap").foregroundStyle(.yellow)
                            Text(L.tapOrDraw)
                        }
                    case .masked:
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle").foregroundStyle(.green)
                            Text(L.tapToRefine)
                        }
                    case .blurred:
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3").foregroundStyle(.blue)
                            Text(L.adjustBlur)
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
