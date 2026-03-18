import Accelerate
import CoreGraphics
import CoreImage
import CoreML
import UIKit

struct LetterboxParams: Sendable {
    let scale: CGFloat
    let resizedWidth: Int
    let resizedHeight: Int
    let padX: Int
    let padY: Int
    let originalSize: CGSize
}

final nonisolated class ImagePreprocessor: Sendable {
    private static let mean: [Float] = [0.485, 0.456, 0.406]
    private static let std: [Float] = [0.229, 0.224, 0.225]
    private static let targetSize = 1024

    // MARK: - Letterbox params

    func computeLetterboxParams(imageSize: CGSize) -> LetterboxParams {
        let target = Self.targetSize
        let maxDim = max(imageSize.width, imageSize.height)
        let scale = CGFloat(target) / maxDim
        // Use floor for consistent rounding (prevents resized > target)
        let resizedW = Int((imageSize.width * scale).rounded(.down))
        let resizedH = Int((imageSize.height * scale).rounded(.down))
        // Ensure resized dimensions don't exceed target
        let clampedW = min(resizedW, target)
        let clampedH = min(resizedH, target)
        let padX = (target - clampedW) / 2
        let padY = (target - clampedH) / 2
        return LetterboxParams(
            scale: scale,
            resizedWidth: clampedW,
            resizedHeight: clampedH,
            padX: padX,
            padY: padY,
            originalSize: imageSize
        )
    }

    // MARK: - Full preprocess (CGImage → MLMultiArray 1×3×1024×1024)

    func preprocess(image: CGImage) -> (MLMultiArray, LetterboxParams)? {
        let origW = image.width
        let origH = image.height
        let params = computeLetterboxParams(
            imageSize: CGSize(width: origW, height: origH)
        )
        let target = Self.targetSize

        // 1. Resize to letterbox dimensions using vImage
        guard let resizedRGBA = resizeCGImage(
            image, toWidth: params.resizedWidth, toHeight: params.resizedHeight
        ) else { return nil }

        // 2. Create MLMultiArray (1×3×1024×1024)
        guard let tensor = try? MLMultiArray(
            shape: [1, 3, NSNumber(value: target), NSNumber(value: target)],
            dataType: .float32
        ) else { return nil }

        let ptr = tensor.dataPointer.assumingMemoryBound(to: Float.self)
        let planeSize = target * target
        // Initialize to zero (padding)
        ptr.initialize(repeating: 0, count: 3 * planeSize)

        // 3. Fill with normalized pixel values at padded position
        let rPlane = ptr
        let gPlane = ptr.advanced(by: planeSize)
        let bPlane = ptr.advanced(by: 2 * planeSize)

        let bytesPerRow = resizedRGBA.count / params.resizedHeight
        let pixelStride = 4 // RGBA

        for y in 0 ..< params.resizedHeight {
            for x in 0 ..< params.resizedWidth {
                let srcIdx = y * bytesPerRow + x * pixelStride
                let dstY = y + params.padY
                let dstX = x + params.padX
                let dstIdx = dstY * target + dstX

                let r = Float(resizedRGBA[srcIdx]) / 255.0
                let g = Float(resizedRGBA[srcIdx + 1]) / 255.0
                let b = Float(resizedRGBA[srcIdx + 2]) / 255.0

                // ImageNet normalization
                rPlane[dstIdx] = (r - Self.mean[0]) / Self.std[0]
                gPlane[dstIdx] = (g - Self.mean[1]) / Self.std[1]
                bPlane[dstIdx] = (b - Self.mean[2]) / Self.std[2]
            }
        }

        return (tensor, params)
    }

    // MARK: - vImage resize

    private func resizeCGImage(
        _ image: CGImage, toWidth width: Int, toHeight height: Int
    ) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let totalBytes = height * bytesPerRow
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self),
            count: totalBytes
        ))
    }
}
