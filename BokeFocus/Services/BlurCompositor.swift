import CoreImage
import CoreImage.CIFilterBuiltins

final nonisolated class BlurCompositor: Sendable {
    private let guidedFilter = GuidedFilter()

    func compositeBlur(
        original: CIImage,
        mask: CIImage,
        blurRadius: Float = 20.0,
        style: BlurStyle = .gaussian
    ) -> CIImage? {
        // 1. Enhanced mask refinement pipeline
        let refined = refineMask(mask, guide: original, extent: original.extent)

        let extent = original.extent

        // 2. Apply selected blur style
        let blurred: CIImage?
        switch style {
        case .gaussian:
            blurred = applyDepthAwareBlur(
                original: original, mask: refined, blurRadius: blurRadius
            )
        case .bokeh:
            blurred = applyBokehBlur(original: original, radius: blurRadius, extent: extent)
        case .zoom:
            blurred = applyZoomBlur(original: original, radius: blurRadius, extent: extent)
        case .motion:
            blurred = applyMotionBlur(original: original, radius: blurRadius, extent: extent)
        case .mosaic:
            blurred = applyMosaic(original: original, radius: blurRadius, extent: extent)
        }

        guard let bg = blurred else { return nil }

        // 3. Composite: sharp foreground + blurred background
        let blend = CIFilter.blendWithMask()
        blend.inputImage = original
        blend.backgroundImage = bg
        blend.maskImage = refined
        return blend.outputImage
    }

    // MARK: - Gaussian (depth-aware)

    private func applyDepthAwareBlur(
        original: CIImage,
        mask: CIImage,
        blurRadius: Float
    ) -> CIImage? {
        let extent = original.extent

        // Scale distance field radius with image resolution
        let resolution = sqrt(extent.width * extent.height)
        let distFieldRadius = max(20.0, 30.0 * (resolution / 1024.0))

        let invertedMask = mask.applyingFilter(
            "CIColorInvert", parameters: [:]
        ).cropped(to: extent)

        // Smooth distance field — larger radius = more gradual depth transition
        let distanceField = invertedMask
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: distFieldRadius]
            )
            .cropped(to: extent)

        // 3-layer blur: light → medium → heavy for natural depth gradient
        let lightBlur = original
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blurRadius * 0.2]
            )
            .cropped(to: extent)

        let mediumBlur = original
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blurRadius * 0.6]
            )
            .cropped(to: extent)

        let heavyBlur = original
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blurRadius]
            )
            .cropped(to: extent)

        // Blend medium+heavy using distance field
        let deepBlend = CIFilter.blendWithMask()
        deepBlend.inputImage = heavyBlur
        deepBlend.backgroundImage = mediumBlur
        deepBlend.maskImage = distanceField
        guard let deepResult = deepBlend.outputImage?.cropped(to: extent) else { return nil }

        // Blend light+deep using a tighter distance field (near-edge transition)
        let nearField = invertedMask
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: distFieldRadius * 0.4]
            )
            .cropped(to: extent)

        let finalBlend = CIFilter.blendWithMask()
        finalBlend.inputImage = deepResult
        finalBlend.backgroundImage = lightBlur
        finalBlend.maskImage = nearField
        return finalBlend.outputImage?.cropped(to: extent)
    }

    // MARK: - Bokeh (lens-like circular bokeh)

    private func applyBokehBlur(
        original: CIImage, radius: Float, extent: CGRect
    ) -> CIImage? {
        original
            .clampedToExtent()
            .applyingFilter("CIBokehBlur", parameters: [
                kCIInputRadiusKey: radius,
                "inputRingAmount": 0.3,
                "inputRingSize": 0.1,
                "inputSoftness": 1.0,
            ])
            .cropped(to: extent)
    }

    // MARK: - Zoom blur (radial)

    private func applyZoomBlur(
        original: CIImage, radius: Float, extent: CGRect
    ) -> CIImage? {
        let center = CIVector(x: extent.midX, y: extent.midY)
        return original
            .clampedToExtent()
            .applyingFilter("CIZoomBlur", parameters: [
                kCIInputCenterKey: center,
                "inputAmount": radius * 0.5,
            ])
            .cropped(to: extent)
    }

    // MARK: - Motion blur (directional)

    private func applyMotionBlur(
        original: CIImage, radius: Float, extent: CGRect
    ) -> CIImage? {
        original
            .clampedToExtent()
            .applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: radius,
                kCIInputAngleKey: 0.0,
            ])
            .cropped(to: extent)
    }

    // MARK: - Mosaic (pixelation)

    private func applyMosaic(
        original: CIImage, radius: Float, extent: CGRect
    ) -> CIImage? {
        let scale = max(2.0, Float(radius) * 0.6)
        return original
            .applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: scale,
                kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY),
            ])
            .cropped(to: extent)
    }

    // MARK: - Enhanced mask refinement

    /// Full refinement pipeline:
    /// 1. Hole filling (morphological close)
    /// 2. Small blob removal (open)
    /// 3. Guided filter (edge-aware refinement using original image)
    /// 4. Edge sharpening
    /// 5. Erode + feather
    private func refineMask(
        _ mask: CIImage, guide: CIImage, extent: CGRect
    ) -> CIImage {
        let nominalRes: CGFloat = 1024.0
        let actualRes = sqrt(extent.width * extent.height)
        let scaleFactor = max(0.5, actualRes / nominalRes)

        // Step 1: Hole filling — morphological close (dilate → erode)
        // Fills small holes inside the foreground mask
        let closeRadius = min(4.0 * scaleFactor, 8.0)
        let closed = mask
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters: [kCIInputRadiusKey: closeRadius]
            )
            .applyingFilter(
                "CIMorphologyMinimum",
                parameters: [kCIInputRadiusKey: closeRadius]
            )
            .cropped(to: extent)

        // Step 2: Small blob removal — morphological open (erode → dilate)
        // Removes small isolated foreground artifacts
        let openRadius = min(3.0 * scaleFactor, 5.0)
        let opened = closed
            .applyingFilter(
                "CIMorphologyMinimum",
                parameters: [kCIInputRadiusKey: openRadius]
            )
            .applyingFilter(
                "CIMorphologyMaximum",
                parameters: [kCIInputRadiusKey: openRadius]
            )
            .cropped(to: extent)

        // Step 3: Guided filter — refine mask edges using original image
        // Lower eps → follows color edges more tightly
        // Subsample capped at 4 to preserve fine detail on high-res
        let guidedRadius = max(8, Int(12.0 * scaleFactor))
        // Adaptive eps: lower on high-res for tighter edge following
        let guidedEps: Float = max(0.004, 0.008 * Float(1024.0 / actualRes))
        let guided = guidedFilter.apply(
            mask: opened,
            guide: guide,
            radius: guidedRadius,
            eps: guidedEps,
            subsample: min(4, max(2, Int(actualRes / 512.0)))
        ) ?? opened

        // Step 4: Sharpen mask edges
        let sharpened = guided
            .applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    kCIInputRadiusKey: min(2.0 * scaleFactor, 3.0),
                    kCIInputIntensityKey: 0.8,
                ]
            )
            .cropped(to: extent)

        // Step 5: Final erode + feather
        // Scale with resolution — no hard clamp for natural-looking transitions
        let morphRadius = min(2.0 * scaleFactor, 4.0)
        let featherRadius = 2.5 * scaleFactor

        let eroded = sharpened
            .applyingFilter(
                "CIMorphologyMinimum",
                parameters: [kCIInputRadiusKey: morphRadius]
            )

        return eroded
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: featherRadius]
            )
            .cropped(to: extent)
    }
}
