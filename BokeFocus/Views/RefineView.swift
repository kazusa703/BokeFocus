import SwiftUI
import UIKit

struct RefineView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var currentStroke: [CGPoint] = []
    @State private var isDrawing = false
    @State private var showResult = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if let displayImage = viewModel.displayImage {
                    Image(uiImage: displayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }

                Canvas { context, _ in
                    if currentStroke.count >= 2 {
                        let color: Color = viewModel.isRefineAdding ? .red.opacity(0.4) : .blue.opacity(0.4)
                        let brushSize = CGFloat(viewModel.brushSize)
                        // Draw connected path for smooth coverage
                        var path = Path()
                        path.move(to: currentStroke[0])
                        for i in 1 ..< currentStroke.count {
                            path.addLine(to: currentStroke[i])
                        }
                        context.stroke(
                            path,
                            with: .color(color),
                            style: StrokeStyle(lineWidth: brushSize, lineCap: .round, lineJoin: .round)
                        )
                    } else if let point = currentStroke.first {
                        let color: Color = viewModel.isRefineAdding ? .red.opacity(0.4) : .blue.opacity(0.4)
                        let brushSize = CGFloat(viewModel.brushSize)
                        let rect = CGRect(
                            x: point.x - brushSize / 2,
                            y: point.y - brushSize / 2,
                            width: brushSize, height: brushSize
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                }
                .allowsHitTesting(false)

                if isDrawing, let lastPoint = currentStroke.last {
                    Circle()
                        .stroke(viewModel.isRefineAdding ? .red : .blue, lineWidth: 1.5)
                        .frame(width: CGFloat(viewModel.brushSize), height: CGFloat(viewModel.brushSize))
                        .position(lastPoint)
                        .allowsHitTesting(false)
                }

                if viewModel.isProcessing {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDrawing { isDrawing = true; currentStroke = [] }
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        isDrawing = false
                        let stroke = currentStroke
                        currentStroke = []
                        Task {
                            await viewModel.applyBrushStroke(
                                points: stroke, viewSize: geometry.size
                            )
                        }
                    }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(L.refine)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.canUndoRefine {
                    Button {
                        Task { await viewModel.undoRefine() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L.next) { showResult = true }
                    .fontWeight(.semibold)
            }
            ToolbarItem(placement: .bottomBar) {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        Button { viewModel.isRefineAdding = true } label: {
                            Label(L.addBlur, systemImage: "plus.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(
                                    viewModel.isRefineAdding ? Color.red.opacity(0.2) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .tint(viewModel.isRefineAdding ? .red : .secondary)

                        Button { viewModel.isRefineAdding = false } label: {
                            Label(L.removeBlur, systemImage: "minus.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(
                                    !viewModel.isRefineAdding ? Color.blue.opacity(0.2) : Color.clear,
                                    in: Capsule()
                                )
                        }
                        .tint(!viewModel.isRefineAdding ? .blue : .secondary)
                    }

                    HStack {
                        Circle().frame(width: 8, height: 8)
                        Slider(value: $viewModel.brushSize, in: 10 ... 80, step: 2)
                        Circle().frame(width: 24, height: 24)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationDestination(isPresented: $showResult) {
            ResultView(viewModel: viewModel)
        }
    }
}
