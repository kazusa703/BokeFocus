import CoreImage
import CoreML
import os
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum EditorState {
    case idle
    case processing
    case masked
    case blurred
}

enum BlurStyle: String, CaseIterable, Identifiable {
    case gaussian
    case bokeh
    case zoom
    case motion
    case mosaic

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .gaussian: "circle.dotted"
        case .bokeh: "sparkle"
        case .zoom: "arrow.up.left.and.arrow.down.right"
        case .motion: "wind"
        case .mosaic: "squareshape.split.2x2"
        }
    }

    var label: String {
        switch self {
        case .gaussian: L.gaussian
        case .bokeh: L.bokeh
        case .zoom: L.zoom
        case .motion: L.motion
        case .mosaic: L.mosaic
        }
    }
}

enum SaveResult {
    case success
    case failure(String)
}

@Observable
final class EditorViewModel {
    private static let logger = Logger(subsystem: "com.imaiissatsu.BokeFocus", category: "Editor")
    // MARK: - Published state

    var originalImage: UIImage?
    var displayImage: UIImage?
    var blurredImage: UIImage?
    var maskOverlayImage: UIImage?
    var editorState: EditorState = .idle
    var blurRadius: Float = 20.0
    var blurStyle: BlurStyle = .gaussian
    var isNegativeMode = false
    var edgeSAMAvailable = false
    var isEncoding = false
    var toastMessage: String?

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

        // Encode in background to avoid blocking UI
        // Use orientation-corrected CGImage to handle EXIF rotation
        if edgeSAMAvailable, let cgImage = normalizedCGImage(from: uiImage) {
            isEncoding = true
            await encodeWithEdgeSAM(cgImage: cgImage)
            isEncoding = false
        }
    }

    /// Preprocess off MainActor, then encode on MainActor (CoreML uses Neural Engine)
    private func encodeWithEdgeSAM(cgImage: CGImage) async {
        // Heavy preprocessing runs off MainActor
        guard let result = await preprocessOffMain(cgImage: cgImage) else {
            return
        }
        // CoreML prediction — dispatches to Neural Engine internally
        letterboxParams = result.params
        do {
            cachedEmbedding = try edgeSAMEngine.encode(imageTensor: result.tensor)
        } catch {
            Self.logger.error("EdgeSAM encode failed: \(error.localizedDescription)")
        }
    }

    private nonisolated func preprocessOffMain(
        cgImage: CGImage
    ) async -> (tensor: MLMultiArray, params: LetterboxParams)? {
        imagePreprocessor.preprocess(image: cgImage)
    }

    /// Normalize UIImage orientation by rendering into a new CGContext
    /// Prevents EXIF rotation from causing misaligned SAM coordinates
    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up {
            return image.cgImage
        }
        let size = image.size
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized?.cgImage
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
            showToast(L.tapOrDraw)
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
                Self.logger.error("EdgeSAM decode failed: \(error.localizedDescription)")
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
            showToast(L.tapOrDraw)
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
            Self.logger.error("Point refinement failed: \(error.localizedDescription)")
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
        updateMaskOverlay()
    }

    /// Generate mask overlay image for visual feedback
    /// Shows selected area with semi-transparent tint
    private func updateMaskOverlay() {
        guard let mask = maskCIImage else {
            maskOverlayImage = nil
            return
        }
        let ciCtx = CIContextManager.shared.context
        guard let cgMask = ciCtx.createCGImage(mask, from: mask.extent) else { return }
        maskOverlayImage = UIImage(cgImage: cgMask)
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
        // Use the actual display scale (same for both axes in AspectFit)
        let screenToImageScale = max(
            imageSize.width / metrics.displayWidth,
            imageSize.height / metrics.displayHeight
        )
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

    /// Offload heavy CIContext rendering off MainActor
    private func applyBlur() async {
        guard let original = originalCIImage,
              let mask = maskCIImage else { return }

        let radius = blurRadius
        let style = blurStyle
        let compositor = blurCompositor

        let uiImage = await renderBlurInBackground(
            compositor: compositor, original: original,
            mask: mask, radius: radius, style: style
        )

        // Check if selection was reset while compositing
        guard maskCIImage != nil, let uiImage else { return }
        blurredImage = uiImage
        displayImage = uiImage
        editorState = .blurred
    }

    /// Nonisolated render to avoid blocking MainActor
    private nonisolated func renderBlurInBackground(
        compositor: BlurCompositor,
        original: CIImage,
        mask: CIImage,
        radius: Float,
        style: BlurStyle
    ) async -> UIImage? {
        guard let output = compositor.compositeBlur(
            original: original, mask: mask, blurRadius: radius, style: style
        ) else { return nil }

        let context = CIContextManager.shared.context
        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Save to Photo Library (with error handling)

    func saveToPhotoLibrary() async -> SaveResult {
        guard let image = blurredImage else { return .failure("No image") }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                guard let data = image.jpegData(compressionQuality: 0.95) else {
                    return
                }
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else {
                    let message = error?.localizedDescription ?? "Save failed"
                    continuation.resume(returning: .failure(message))
                }
            }
        }
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
        blurStyle = .gaussian
        isNegativeMode = false
        isRefineAdding = true
        brushSize = 30.0
        isEncoding = false
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message { toastMessage = nil }
        }
    }
}
