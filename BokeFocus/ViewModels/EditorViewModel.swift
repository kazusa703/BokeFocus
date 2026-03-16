import CoreImage
import CoreML
import PhotosUI
import SwiftUI
import UIKit

enum EditorState {
    case idle
    case processing
    case masked
    case blurred
}

@Observable
final class EditorViewModel {
    // MARK: - Published state

    var originalImage: UIImage?
    var displayImage: UIImage?
    var blurredImage: UIImage?
    var maskOverlayImage: UIImage?
    var editorState: EditorState = .idle
    var blurRadius: Float = 20.0
    var isNegativeMode = false
    var edgeSAMAvailable = false

    // Refine state
    var isRefineAdding = true // true = add blur, false = remove blur
    var brushSize: Float = 30.0

    // Selection state
    var bboxStart: CGPoint?
    var bboxEnd: CGPoint?
    var additionalPoints: [(point: CGPoint, isPositive: Bool)] = []

    var isProcessing: Bool {
        editorState == .processing
    }

    var hasMask: Bool {
        maskCIImage != nil
    }

    // MARK: - Private

    private var originalCIImage: CIImage?
    private var maskCIImage: CIImage?
    private var maskBitmap: CGContext?
    private var maskBitmapSize: CGSize = .zero
    private let visionEngine = VisionEngine()
    private let blurCompositor = BlurCompositor()
    private let coordinateConverter = CoordinateConverter()
    private let imagePreprocessor = ImagePreprocessor()
    private let edgeSAMEngine = EdgeSAMEngine()
    private let maskPostprocessor = MaskPostprocessor()
    private var undoStack: [UndoAction] = []

    // Refine undo
    private var refineUndoStack: [CGImage] = []
    var canUndoRefine: Bool {
        !refineUndoStack.isEmpty
    }

    // EdgeSAM cached state
    private var cachedEmbedding: MLMultiArray?
    private var letterboxParams: LetterboxParams?

    private enum UndoAction {
        case initialMask(CIImage)
        case addPoint(index: Int)
    }

    // MARK: - Init

    init() {
        edgeSAMEngine.loadModels()
        edgeSAMAvailable = edgeSAMEngine.isLoaded
    }

    // MARK: - Load image

    func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        resetState()
        originalImage = uiImage
        displayImage = uiImage
        originalCIImage = CIImage(image: uiImage)

        if edgeSAMAvailable, let cgImage = uiImage.cgImage {
            encodeWithEdgeSAM(cgImage: cgImage)
        }
    }

    private func encodeWithEdgeSAM(cgImage: CGImage) {
        guard let (tensor, params) = imagePreprocessor.preprocess(image: cgImage) else {
            return
        }
        letterboxParams = params
        do {
            cachedEmbedding = try edgeSAMEngine.encode(imageTensor: tensor)
        } catch {
            print("[EdgeSAM] Encode failed: \(error)")
        }
    }

    // MARK: - Tap → Vision auto-detect

    func handleTap(at point: CGPoint, viewSize: CGSize) async {
        guard let original = originalCIImage else { return }

        if hasMask {
            let newPoint = (point: point, isPositive: !isNegativeMode)
            additionalPoints.append(newPoint)
            undoStack.append(.addPoint(index: additionalPoints.count - 1))
            if cachedEmbedding != nil, let params = letterboxParams {
                await runEdgeSAMWithPoints(viewSize: viewSize, params: params)
            }
            return
        }

        editorState = .processing

        let imagePoint = coordinateConverter.screenToImagePoint(
            screenPoint: point,
            viewSize: viewSize,
            imageSize: original.extent.size
        )

        if let mask = await visionEngine.detectForeground(
            image: original,
            tapPoint: imagePoint
        ) {
            maskCIImage = mask
            undoStack = []
            editorState = .masked
            initMaskBitmap()
            await applyBlur()
        } else {
            editorState = .idle
        }
    }

    // MARK: - BBox → EdgeSAM or Vision fallback

    func handleBBox(start: CGPoint, end: CGPoint, viewSize: CGSize) async {
        guard let original = originalCIImage else { return }
        editorState = .processing
        bboxStart = start
        bboxEnd = end
        additionalPoints = []

        if let embedding = cachedEmbedding, let params = letterboxParams {
            guard let prompt = coordinateConverter.boundingBoxToSAMPrompt(
                startScreen: start, endScreen: end,
                viewSize: viewSize, params: params
            ) else {
                editorState = .idle
                return
            }

            do {
                if let result = try edgeSAMEngine.decode(
                    embedding: embedding,
                    coords: prompt.coords,
                    labels: prompt.labels
                ),
                    let ciMask = maskPostprocessor.process(
                        rawMask: result.mask, params: params, threshold: 0.0
                    )
                {
                    maskCIImage = ciMask
                    undoStack = []
                    editorState = .masked
                    initMaskBitmap()
                    await applyBlur()
                    return
                }
            } catch {
                print("[EdgeSAM] Decode failed: \(error)")
            }
        }

        // Vision fallback
        let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let imagePoint = coordinateConverter.screenToImagePoint(
            screenPoint: center, viewSize: viewSize,
            imageSize: original.extent.size
        )

        if let mask = await visionEngine.detectForeground(
            image: original, tapPoint: imagePoint
        ) {
            maskCIImage = mask
            undoStack = []
            editorState = .masked
            initMaskBitmap()
            await applyBlur()
        } else {
            editorState = .idle
        }
    }

    // MARK: - EdgeSAM point refinement

    private func runEdgeSAMWithPoints(
        viewSize: CGSize, params: LetterboxParams
    ) async {
        guard let embedding = cachedEmbedding else { return }
        guard let prompt = coordinateConverter.pointsToSAMPrompt(
            screenPoints: additionalPoints,
            bboxStart: bboxStart, bboxEnd: bboxEnd,
            viewSize: viewSize, params: params
        ) else { return }

        do {
            if let result = try edgeSAMEngine.decode(
                embedding: embedding,
                coords: prompt.coords, labels: prompt.labels
            ),
                let ciMask = maskPostprocessor.process(
                    rawMask: result.mask, params: params, threshold: 0.0
                )
            {
                maskCIImage = ciMask
                editorState = .masked
                initMaskBitmap()
                await applyBlur()
            }
        } catch {
            print("[EdgeSAM] Point refinement failed: \(error)")
        }
    }

    // MARK: - Brush stroke mask editing (Refine)

    /// Initialize editable mask bitmap from current CIImage mask
    private func initMaskBitmap() {
        guard let mask = maskCIImage,
              let original = originalCIImage else { return }

        let width = Int(original.extent.width)
        let height = Int(original.extent.height)
        maskBitmapSize = CGSize(width: width, height: height)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }

        // Render current mask into bitmap
        let ciCtx = CIContextManager.shared.context
        if let cgMask = ciCtx.createCGImage(mask, from: mask.extent) {
            ctx.draw(cgMask, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        maskBitmap = ctx
        refineUndoStack = []
    }

    /// Apply brush stroke: points in screen coordinates
    func applyBrushStroke(points: [CGPoint], viewSize: CGSize) async {
        guard let ctx = maskBitmap,
              let original = originalCIImage,
              points.count >= 2 else { return }

        // Save current state for undo
        if let currentCG = ctx.makeImage() {
            refineUndoStack.append(currentCG)
            if refineUndoStack.count > 30 { refineUndoStack.removeFirst() }
        }

        let imageSize = original.extent.size
        let metrics = coordinateConverter.aspectFitMetrics(
            imageSize: imageSize, viewSize: viewSize
        )

        // Convert brush size from screen to image pixels
        let screenToImageScale = imageSize.width / metrics.displayWidth
        let imageBrushSize = CGFloat(brushSize) * screenToImageScale

        // Draw on mask bitmap
        // White = foreground (sharp), Black = background (blurred)
        // "Add blur" = paint BLACK, "Remove blur" = paint WHITE
        if isRefineAdding {
            ctx.setFillColor(gray: 0, alpha: 1) // Black = blurred
            ctx.setStrokeColor(gray: 0, alpha: 1)
        } else {
            ctx.setFillColor(gray: 1, alpha: 1) // White = sharp
            ctx.setStrokeColor(gray: 1, alpha: 1)
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(imageBrushSize)

        let bitmapHeight = CGFloat(ctx.height)

        ctx.beginPath()
        for (i, screenPt) in points.enumerated() {
            let imgPt = coordinateConverter.screenToImagePoint(
                screenPoint: screenPt,
                viewSize: viewSize,
                imageSize: imageSize
            )
            // CGContext has flipped Y (origin at bottom-left)
            let flippedY = bitmapHeight - imgPt.y
            if i == 0 {
                ctx.move(to: CGPoint(x: imgPt.x, y: flippedY))
            } else {
                ctx.addLine(to: CGPoint(x: imgPt.x, y: flippedY))
            }
        }
        ctx.strokePath()

        // Also draw circles at each point for smoother coverage
        for screenPt in points {
            let imgPt = coordinateConverter.screenToImagePoint(
                screenPoint: screenPt,
                viewSize: viewSize,
                imageSize: imageSize
            )
            let flippedY = bitmapHeight - imgPt.y
            let r = imageBrushSize / 2
            ctx.fillEllipse(in: CGRect(
                x: imgPt.x - r, y: flippedY - r,
                width: imageBrushSize, height: imageBrushSize
            ))
        }

        // Convert bitmap back to CIImage
        guard let updatedCG = ctx.makeImage() else { return }
        maskCIImage = CIImage(cgImage: updatedCG)

        // Recomposite blur
        await applyBlur()
    }

    /// Undo last brush stroke
    func undoRefine() async {
        guard let previousCG = refineUndoStack.popLast(),
              let ctx = maskBitmap else { return }

        let width = ctx.width
        let height = ctx.height
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(previousCG, in: CGRect(x: 0, y: 0, width: width, height: height))

        maskCIImage = CIImage(cgImage: previousCG)
        await applyBlur()
    }

    // MARK: - Blur

    func reapplyBlur() async {
        await applyBlur()
    }

    private func applyBlur() async {
        guard let original = originalCIImage,
              let mask = maskCIImage else { return }

        let result = blurCompositor.compositeBlur(
            original: original, mask: mask, blurRadius: blurRadius
        )

        guard let output = result else { return }
        // Check if selection was reset while compositing
        guard maskCIImage != nil else { return }

        let context = CIContextManager.shared.context
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return }
        blurredImage = UIImage(cgImage: cgImage)
        displayImage = blurredImage
        editorState = .blurred
    }

    // MARK: - Undo (editor)

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        switch action {
        case .addPoint:
            if !additionalPoints.isEmpty { additionalPoints.removeLast() }
        case .initialMask:
            maskCIImage = nil
            maskOverlayImage = nil
            blurredImage = nil
            displayImage = originalImage
            bboxStart = nil
            bboxEnd = nil
            additionalPoints = []
            editorState = .idle
        }
    }

    // MARK: - Reset

    func resetSelection() {
        maskCIImage = nil
        maskOverlayImage = nil
        maskBitmap = nil
        blurredImage = nil
        displayImage = originalImage
        bboxStart = nil
        bboxEnd = nil
        additionalPoints = []
        undoStack = []
        refineUndoStack = []
        editorState = .idle
    }

    private func resetState() {
        originalImage = nil
        displayImage = nil
        blurredImage = nil
        maskOverlayImage = nil
        originalCIImage = nil
        maskCIImage = nil
        maskBitmap = nil
        cachedEmbedding = nil
        letterboxParams = nil
        bboxStart = nil
        bboxEnd = nil
        additionalPoints = []
        undoStack = []
        refineUndoStack = []
        editorState = .idle
        blurRadius = 20.0
        isNegativeMode = false
        isRefineAdding = true
        brushSize = 30.0
    }
}
