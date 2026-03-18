import Accelerate
import CoreGraphics
import CoreImage

/// Fast Guided Filter implementation using Accelerate framework.
///
/// Refines a mask using the original image's edge information.
/// Operates at reduced resolution for speed, then upscales the result.
///
/// Algorithm: q_i = a_k * I_i + b_k (local linear model)
/// Where a and b are computed from local statistics of guide and input.
final nonisolated class GuidedFilter: Sendable {
    /// Apply guided filter to refine mask edges using original image.
    ///
    /// - Parameters:
    ///   - mask: Grayscale CIImage (0-255, white = foreground)
    ///   - guide: Original image (CIImage)
    ///   - radius: Filter window radius (in reduced-resolution pixels)
    ///   - eps: Regularization (smaller = follow edges more closely)
    ///   - subsample: Downsampling factor for speed (e.g., 4 = 1/4 resolution)
    /// - Returns: Refined mask CIImage at original resolution
    func apply(
        mask: CIImage,
        guide: CIImage,
        radius: Int = 16,
        eps: Float = 0.01,
        subsample: Int = 4
    ) -> CIImage? {
        let extent = mask.extent
        let ciCtx = CIContextManager.shared.context

        // Work at reduced resolution for speed
        let targetW = max(Int(extent.width) / subsample, 64)
        let targetH = max(Int(extent.height) / subsample, 64)

        // Convert guide to grayscale at reduced resolution
        let guideGray = guide
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0])
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(targetW) / extent.width,
                y: CGFloat(targetH) / extent.height
            ))
            .cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        // Downsample mask
        let maskDown = mask
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(targetW) / extent.width,
                y: CGFloat(targetH) / extent.height
            ))
            .cropped(to: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        // Render to pixel buffers
        guard let guidePixels = renderToFloatArray(ciCtx: ciCtx, image: guideGray, width: targetW, height: targetH),
              var maskPixels = renderToFloatArray(ciCtx: ciCtx, image: maskDown, width: targetW, height: targetH)
        else { return nil }

        // Apply guided filter algorithm
        var guideArray = guidePixels
        guard var result = guidedFilterCore(
            guide: &guideArray,
            input: &maskPixels,
            width: targetW,
            height: targetH,
            radius: radius,
            eps: eps
        ) else { return nil }

        // Convert result back to CIImage
        guard let resultCI = floatArrayToCIImage(
            pixels: &result, width: targetW, height: targetH
        ) else { return nil }

        // Upscale back to original resolution with smooth interpolation
        return resultCI
            .samplingLinear()
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / CGFloat(targetW),
                y: extent.height / CGFloat(targetH)
            ))
            .cropped(to: extent)
    }

    // MARK: - Core algorithm

    /// Guided filter core: computes local linear coefficients a, b
    /// using box filter for mean computation.
    private func guidedFilterCore(
        guide: inout [Float],
        input: inout [Float],
        width: Int,
        height: Int,
        radius: Int,
        eps: Float
    ) -> [Float]? {
        let count = width * height

        // Normalize to 0-1 range
        var scale: Float = 1.0 / 255.0
        vDSP_vsmul(guide, 1, &scale, &guide, 1, vDSP_Length(count))
        vDSP_vsmul(input, 1, &scale, &input, 1, vDSP_Length(count))

        // mean_I = boxfilter(I)
        let meanI = boxFilter(guide, width: width, height: height, radius: radius)

        // mean_p = boxfilter(p)
        let meanP = boxFilter(input, width: width, height: height, radius: radius)

        // mean_Ip = boxfilter(I * p)
        var Ip = [Float](repeating: 0, count: count)
        vDSP_vmul(guide, 1, input, 1, &Ip, 1, vDSP_Length(count))
        let meanIp = boxFilter(Ip, width: width, height: height, radius: radius)

        // mean_II = boxfilter(I * I)
        var II = [Float](repeating: 0, count: count)
        vDSP_vsq(guide, 1, &II, 1, vDSP_Length(count))
        let meanII = boxFilter(II, width: width, height: height, radius: radius)

        // cov_Ip = mean_Ip - mean_I * mean_p
        var covIp = [Float](repeating: 0, count: count)
        vDSP_vmul(meanI, 1, meanP, 1, &covIp, 1, vDSP_Length(count))
        vDSP_vsub(covIp, 1, meanIp, 1, &covIp, 1, vDSP_Length(count))

        // var_I = mean_II - mean_I * mean_I
        var varI = [Float](repeating: 0, count: count)
        vDSP_vsq(meanI, 1, &varI, 1, vDSP_Length(count))
        vDSP_vsub(varI, 1, meanII, 1, &varI, 1, vDSP_Length(count))

        // a = cov_Ip / (var_I + eps)
        let epsVec = [Float](repeating: eps, count: count)
        var denom = [Float](repeating: 0, count: count)
        vDSP_vadd(varI, 1, epsVec, 1, &denom, 1, vDSP_Length(count))

        var a = [Float](repeating: 0, count: count)
        vDSP_vdiv(denom, 1, covIp, 1, &a, 1, vDSP_Length(count))

        // b = mean_p - a * mean_I
        var aMeanI = [Float](repeating: 0, count: count)
        vDSP_vmul(a, 1, meanI, 1, &aMeanI, 1, vDSP_Length(count))
        var b = [Float](repeating: 0, count: count)
        vDSP_vsub(aMeanI, 1, meanP, 1, &b, 1, vDSP_Length(count))

        // mean_a, mean_b
        let meanA = boxFilter(a, width: width, height: height, radius: radius)
        let meanB = boxFilter(b, width: width, height: height, radius: radius)

        // q = mean_a * I + mean_b
        var result = [Float](repeating: 0, count: count)
        vDSP_vmul(meanA, 1, guide, 1, &result, 1, vDSP_Length(count))
        vDSP_vadd(result, 1, meanB, 1, &result, 1, vDSP_Length(count))

        // Scale back to 0-255 and clamp
        var scale255: Float = 255.0
        vDSP_vsmul(result, 1, &scale255, &result, 1, vDSP_Length(count))
        var lo: Float = 0
        var hi: Float = 255
        vDSP_vclip(result, 1, &lo, &hi, &result, 1, vDSP_Length(count))

        return result
    }

    // MARK: - Box filter (normalized)

    /// Efficient box filter using cumulative sums (integral image approach).
    private func boxFilter(
        _ input: [Float], width: Int, height: Int, radius: Int
    ) -> [Float] {
        let count = width * height
        var output = [Float](repeating: 0, count: count)
        var temp = [Float](repeating: 0, count: count)

        // Horizontal pass: row-wise cumulative sum windowed
        for y in 0 ..< height {
            var sum: Float = 0
            let rowStart = y * width

            // Initialize sum for first window
            for x in 0 ... min(radius, width - 1) {
                sum += input[rowStart + x]
            }
            temp[rowStart] = sum

            for x in 1 ..< width {
                let addX = x + radius
                let subX = x - radius - 1
                if addX < width { sum += input[rowStart + addX] }
                if subX >= 0 { sum -= input[rowStart + subX] }
                temp[rowStart + x] = sum
            }
        }

        // Vertical pass: column-wise cumulative sum windowed
        for x in 0 ..< width {
            var sum: Float = 0

            for y in 0 ... min(radius, height - 1) {
                sum += temp[y * width + x]
            }
            output[x] = sum

            for y in 1 ..< height {
                let addY = y + radius
                let subY = y - radius - 1
                if addY < height { sum += temp[addY * width + x] }
                if subY >= 0 { sum -= temp[subY * width + x] }
                output[y * width + x] = sum
            }
        }

        // Normalize by window area (handle borders)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let yMin = max(0, y - radius)
                let yMax = min(height - 1, y + radius)
                let xMin = max(0, x - radius)
                let xMax = min(width - 1, x + radius)
                let area = Float((yMax - yMin + 1) * (xMax - xMin + 1))
                output[y * width + x] /= area
            }
        }

        return output
    }

    // MARK: - Image conversion helpers

    private func renderToFloatArray(
        ciCtx: CIContext, image: CIImage, width: Int, height: Int
    ) -> [Float]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let cgImage = ciCtx.createCGImage(
            image, from: CGRect(x: 0, y: 0, width: width, height: height)
        ) else { return nil }

        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)

        var floats = [Float](repeating: 0, count: width * height)
        for i in 0 ..< width * height {
            floats[i] = Float(bytes[i])
        }
        return floats
    }

    private func floatArrayToCIImage(
        pixels: inout [Float], width: Int, height: Int
    ) -> CIImage? {
        // Convert float (0-255) to UInt8
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in 0 ..< width * height {
            bytes[i] = UInt8(max(0, min(255, pixels[i])))
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cgImage = CGImage(
                  width: width, height: height,
                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return nil }

        return CIImage(cgImage: cgImage)
    }
}
