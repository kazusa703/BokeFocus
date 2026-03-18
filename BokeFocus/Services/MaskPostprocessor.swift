import Accelerate
import CoreGraphics
import CoreImage
import CoreML

final nonisolated class MaskPostprocessor {
    private let ciContext = CIContextManager.shared.context

    // MARK: - Process EdgeSAM decoder output → CIImage mask

    /// Convert raw decoder output (MLMultiArray logits) to a refined mask CIImage
    /// at the original image size.
    ///
    /// Pipeline: remove padding → upscale logits → sharpen edges → threshold
    func process(
        rawMask: MLMultiArray,
        params: LetterboxParams,
        threshold: Float = 0.0
    ) -> CIImage? {
        let maskShape = rawMask.shape.map { $0.intValue }
        let maskH: Int
        let maskW: Int

        switch maskShape.count {
        case 4:
            maskH = maskShape[2]
            maskW = maskShape[3]
        case 3:
            maskH = maskShape[1]
            maskW = maskShape[2]
        case 2:
            maskH = maskShape[0]
            maskW = maskShape[1]
        default:
            return nil
        }

        let ptr = rawMask.dataPointer.assumingMemoryBound(to: Float.self)

        // 1. Compute mask-space padding
        let padMaskX = Int((CGFloat(params.padX) * CGFloat(maskW) / 1024.0).rounded())
        let padMaskY = Int((CGFloat(params.padY) * CGFloat(maskH) / 1024.0).rounded())
        let contentW = Int((CGFloat(params.resizedWidth) * CGFloat(maskW) / 1024.0).rounded())
        let contentH = Int((CGFloat(params.resizedHeight) * CGFloat(maskH) / 1024.0).rounded())

        guard contentW > 0, contentH > 0 else { return nil }

        // 2. Extract content region as float logits
        var logitsPixels = [Float](repeating: 0, count: contentW * contentH)
        for y in 0 ..< contentH {
            for x in 0 ..< contentW {
                let srcY = y + padMaskY
                let srcX = x + padMaskX
                guard srcX >= 0, srcX < maskW, srcY >= 0, srcY < maskH else { continue }
                let srcIdx = srcY * maskW + srcX
                logitsPixels[y * contentW + x] = ptr[srcIdx]
            }
        }

        // 3. Create float CIImage from logits
        guard let logitsCIImage = createFloatCIImage(
            pixels: &logitsPixels, width: contentW, height: contentH
        ) else { return nil }

        // 4. Upscale logits to original image size (bilinear in logits space)
        let scaleX = params.originalSize.width / CGFloat(contentW)
        let scaleY = params.originalSize.height / CGFloat(contentH)
        let upscaled = logitsCIImage
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: params.originalSize))

        // 5. Multi-pass edge sharpening in logits space (before threshold)
        let resolution = sqrt(params.originalSize.width * params.originalSize.height)
        let sharpenRadius = min(2.0, 1.5 * (resolution / 2000.0))
        let sharpened = upscaled
            .applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    kCIInputRadiusKey: sharpenRadius,
                    kCIInputIntensityKey: 0.7,
                ]
            )
            .cropped(to: CGRect(origin: .zero, size: params.originalSize))

        // 6. Threshold at full resolution
        guard let cgSharpened = ciContext.createCGImage(
            sharpened, from: sharpened.extent
        ) else { return nil }

        return thresholdToMask(cgSharpened, threshold: threshold, imageResolution: resolution)
    }

    // MARK: - Create float CIImage from logits array

    private func createFloatCIImage(
        pixels: inout [Float], width: Int, height: Int
    ) -> CIImage? {
        let bytesPerRow = width * MemoryLayout<Float>.size
        let data = Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.none.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 32,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { return nil }

        return CIImage(cgImage: cgImage)
    }

    // MARK: - Resolution-adaptive threshold

    private func thresholdToMask(
        _ image: CGImage, threshold: Float, imageResolution: CGFloat
    ) -> CIImage? {
        let w = image.width
        let h = image.height

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = w * MemoryLayout<Float>.size
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.none.rawValue
                | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 32, bytesPerRow: bytesPerRow,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = ctx.data else { return nil }
        let floatPtr = data.assumingMemoryBound(to: Float.self)

        // Adaptive ramp width: narrower on high-res images for sharper edges
        // More aggressive sharpening than before
        let rampWidth: Float = max(0.15, 0.4 * Float(1024.0 / imageResolution))

        var binaryPixels = [UInt8](repeating: 0, count: w * h)
        for i in 0 ..< w * h {
            let value = floatPtr[i]
            // Sigmoid-like soft threshold with adaptive width
            let normalized = (value - threshold) / rampWidth
            let clamped = max(0.0, min(1.0, normalized * 0.5 + 0.5))
            binaryPixels[i] = UInt8(clamped * 255.0)
        }

        guard let provider = CGDataProvider(data: Data(binaryPixels) as CFData),
              let cgMask = CGImage(
                  width: w, height: h,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }

        return CIImage(cgImage: cgMask)
    }
}
