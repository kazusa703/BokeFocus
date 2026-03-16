import CoreImage
import CoreImage.CIFilterBuiltins

final class BlurCompositor {
    func compositeBlur(
        original: CIImage,
        mask: CIImage,
        blurRadius: Float = 20.0
    ) -> CIImage? {
        // 1. Refine mask edges
        let refined = refineMask(mask, extent: original.extent)

        // 2. Create depth-aware blur gradient
        // Near foreground edge = less blur, far from edge = full blur
        let depthBlurred = applyDepthAwareBlur(
            original: original, mask: refined, blurRadius: blurRadius
        )

        guard let blurred = depthBlurred else { return nil }

        // 3. Composite: sharp foreground + blurred background
        let blend = CIFilter.blendWithMask()
        blend.inputImage = original
        blend.backgroundImage = blurred
        blend.maskImage = refined
        return blend.outputImage
    }

    // MARK: - Depth-aware blur (graduated falloff)

    /// Creates a more realistic blur by varying intensity based on
    /// distance from the foreground edge. Objects near the subject
    /// are blurred less than distant background.
    private func applyDepthAwareBlur(
        original: CIImage,
        mask: CIImage,
        blurRadius: Float
    ) -> CIImage? {
        let extent = original.extent

        // Create distance-based blur map from mask
        // Dilate mask progressively → pixels that become white later are "closer" to foreground
        let invertedMask = mask.applyingFilter(
            "CIColorInvert", parameters: [:]
        ).cropped(to: extent)

        // Blur the inverted mask to create a smooth distance field
        // Areas far from foreground = high value = more blur
        let distanceField = invertedMask
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: 30.0]
            )
            .cropped(to: extent)

        // Apply two blur levels and blend based on distance
        let lightBlur = original
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blurRadius * 0.4]
            )
            .cropped(to: extent)

        let heavyBlur = original
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: blurRadius]
            )
            .cropped(to: extent)

        // Blend: near foreground = light blur, far = heavy blur
        let gradientBlend = CIFilter.blendWithMask()
        gradientBlend.inputImage = heavyBlur
        gradientBlend.backgroundImage = lightBlur
        gradientBlend.maskImage = distanceField
        return gradientBlend.outputImage?.cropped(to: extent)
    }

    // MARK: - Mask refinement with resolution-adaptive parameters

    private func refineMask(_ mask: CIImage, extent: CGRect) -> CIImage {
        let nominalRes: CGFloat = 1024.0
        let actualRes = sqrt(extent.width * extent.height)
        let scaleFactor = max(0.5, actualRes / nominalRes)

        // Cap feather radius to prevent halos on high-res images
        let morphRadius = min(2.0 * scaleFactor, 4.0)
        let featherRadius = min(2.5 * scaleFactor, 4.0)

        // Sharpen mask edges before morphology
        let sharpened = mask
            .applyingFilter(
                "CIUnsharpMask",
                parameters: [
                    kCIInputRadiusKey: min(2.0 * scaleFactor, 3.0),
                    kCIInputIntensityKey: 0.6,
                ]
            )
            .cropped(to: extent)

        // Erode to remove fringe artifacts at foreground/background boundary
        let eroded = sharpened
            .applyingFilter(
                "CIMorphologyMinimum",
                parameters: [kCIInputRadiusKey: morphRadius]
            )

        // Feather for smooth foreground-to-background transition
        return eroded
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: featherRadius]
            )
            .cropped(to: extent)
    }
}
