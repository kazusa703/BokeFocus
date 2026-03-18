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
        let mask: MLMultiArray // [256, 256] logits — weighted blend of top masks
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

        let masksPtr = masks.dataPointer.assumingMemoryBound(to: Float.self)

        // Compute stability score for each of the 4 candidate masks
        var maskInfos: [(index: Int, stability: Float, iou: Float)] = []
        for i in 0 ..< 4 {
            let offset = i * planeSize
            let stability = computeStabilityScore(
                logits: masksPtr.advanced(by: offset),
                count: planeSize,
                threshold: 0.0,
                offset: 1.0
            )
            let iouScore = scores[[0, NSNumber(value: i)] as [NSNumber]].floatValue
            maskInfos.append((index: i, stability: stability, iou: iouScore))
        }

        // Sort by stability (desc), then IoU (desc)
        maskInfos.sort {
            if $0.stability != $1.stability { return $0.stability > $1.stability }
            return $0.iou > $1.iou
        }

        // Weighted blend of top-2 masks in logits space
        // Better boundary quality than picking single best mask
        guard let blended = weightedBlendTopMasks(
            masksPtr: masksPtr,
            maskInfos: maskInfos,
            planeSize: planeSize,
            topK: 2
        ) else { return nil }

        return DecoderResult(
            mask: blended,
            score: maskInfos[0].iou,
            stabilityScore: maskInfos[0].stability,
            allMasks: masks
        )
    }

    // MARK: - Weighted logits blend

    /// Blend top-K masks using stability scores as weights.
    /// This produces smoother, more confident boundaries than
    /// picking a single mask.
    private func weightedBlendTopMasks(
        masksPtr: UnsafePointer<Float>,
        maskInfos: [(index: Int, stability: Float, iou: Float)],
        planeSize: Int,
        topK: Int
    ) -> MLMultiArray? {
        let k = min(topK, maskInfos.count)

        // Compute softmax-like weights from stability scores
        var weights = [Float](repeating: 0, count: k)
        var maxStab: Float = -Float.infinity
        for i in 0 ..< k {
            maxStab = max(maxStab, maskInfos[i].stability)
        }
        var sumExp: Float = 0
        for i in 0 ..< k {
            // Temperature=5.0 → sharper weighting toward best mask
            let w = exp((maskInfos[i].stability - maxStab) * 5.0)
            weights[i] = w
            sumExp += w
        }
        for i in 0 ..< k {
            weights[i] /= sumExp
        }

        guard let result = try? MLMultiArray(
            shape: [1, 1, 256, 256 as NSNumber],
            dataType: .float32
        ) else { return nil }
        let dstPtr = result.dataPointer.assumingMemoryBound(to: Float.self)

        // Initialize to zero
        dstPtr.update(repeating: 0, count: planeSize)

        // Accumulate weighted logits
        for i in 0 ..< k {
            let srcOffset = maskInfos[i].index * planeSize
            let w = weights[i]
            for j in 0 ..< planeSize {
                dstPtr[j] += masksPtr[srcOffset + j] * w
            }
        }

        return result
    }

    // MARK: - Stability Score

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
}
