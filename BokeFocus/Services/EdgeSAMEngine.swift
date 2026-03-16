import CoreImage
import CoreML

/// EdgeSAM Encoder/Decoder wrapper using Xcode auto-generated typed API.
///
/// Encoder: image [1,3,1024,1024] → image_embeddings [1,256,64,64]
/// Decoder: image_embeddings + point_coords [1,N,2] + point_labels [1,N]
///          → masks [1,4,256,256] + scores [1,4]
final class EdgeSAMEngine {
    private var encoder: EdgeSAMEncoder?
    private var decoder: EdgeSAMDecoder?

    var isLoaded: Bool {
        encoder != nil && decoder != nil
    }

    // MARK: - Load

    func loadModels() {
        let config = MLModelConfiguration()
        config.computeUnits = .all

        encoder = try? EdgeSAMEncoder(configuration: config)
        decoder = try? EdgeSAMDecoder(configuration: config)

        if isLoaded {
            print("[EdgeSAM] Models loaded successfully")
        } else {
            print("[EdgeSAM] Models not found — Vision-only mode")
        }
    }

    // MARK: - Encode (~100ms, run once per image)

    func encode(imageTensor: MLMultiArray) throws -> MLMultiArray? {
        guard let encoder else { return nil }
        let output = try encoder.prediction(image: imageTensor)
        return output.image_embeddings
    }

    // MARK: - Decode (~12ms, run per interaction)

    struct DecoderResult {
        let mask: MLMultiArray // [256, 256] logits
        let score: Float
        let stabilityScore: Float
        let allMasks: MLMultiArray // [1, 4, 256, 256]
    }

    func decode(
        embedding: MLMultiArray,
        coords: MLMultiArray,
        labels: MLMultiArray
    ) throws -> DecoderResult? {
        guard let decoder else { return nil }

        let output = try decoder.prediction(
            image_embeddings: embedding,
            point_coords: coords,
            point_labels: labels
        )

        let scores = output.scores
        let masks = output.masks
        let planeSize = 256 * 256

        // Select best mask using stability score (more reliable than IoU score)
        let masksPtr = masks.dataPointer.assumingMemoryBound(to: Float.self)

        var bestIdx = 0
        var bestStability: Float = -Float.infinity
        var bestIoUScore: Float = -Float.infinity

        for i in 0 ..< 4 {
            let offset = i * planeSize
            let stability = computeStabilityScore(
                logits: masksPtr.advanced(by: offset),
                count: planeSize,
                threshold: 0.0,
                offset: 1.0
            )
            let iouScore = scores[[0, NSNumber(value: i)] as [NSNumber]].floatValue

            // Primary: stability score, secondary: IoU score
            if stability > bestStability ||
                (stability == bestStability && iouScore > bestIoUScore)
            {
                bestStability = stability
                bestIoUScore = iouScore
                bestIdx = i
            }
        }

        guard let bestMask = extractMask(
            from: masks, index: bestIdx, height: 256, width: 256
        ) else { return nil }

        return DecoderResult(
            mask: bestMask,
            score: bestIoUScore,
            stabilityScore: bestStability,
            allMasks: masks
        )
    }

    // MARK: - Stability Score

    /// Compute stability score: IoU between masks thresholded at
    /// (threshold - offset) and (threshold + offset).
    /// A high score means the mask boundary is confident / stable.
    private func computeStabilityScore(
        logits: UnsafePointer<Float>,
        count: Int,
        threshold: Float,
        offset: Float
    ) -> Float {
        var intersection = 0
        var union = 0

        let highThresh = threshold + offset
        let lowThresh = threshold - offset

        for i in 0 ..< count {
            let v = logits[i]
            let high = v > highThresh
            let low = v > lowThresh

            if high && low { intersection += 1 }
            if high || low { union += 1 }
        }

        return union > 0 ? Float(intersection) / Float(union) : 0.0
    }

    // MARK: - Extract single mask from 4-candidate output

    private func extractMask(
        from allMasks: MLMultiArray,
        index: Int,
        height: Int,
        width: Int
    ) -> MLMultiArray? {
        guard let single = try? MLMultiArray(
            shape: [1, 1, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        ) else { return nil }

        let srcPtr = allMasks.dataPointer.assumingMemoryBound(to: Float.self)
        let dstPtr = single.dataPointer.assumingMemoryBound(to: Float.self)
        let planeSize = height * width
        let srcOffset = index * planeSize

        dstPtr.update(from: srcPtr.advanced(by: srcOffset), count: planeSize)

        return single
    }
}
