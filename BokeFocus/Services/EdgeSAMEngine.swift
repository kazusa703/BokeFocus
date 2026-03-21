import Accelerate
import CoreImage
import CoreML
import os

/// EdgeSAM Encoder/Decoder wrapper using Xcode auto-generated typed API.
///
/// Encoder: image [1,3,1024,1024] → image_embeddings [1,256,64,64]
/// Decoder: image_embeddings + point_coords [1,N,2] + point_labels [1,N]
///          → masks [1,4,256,256] + scores [1,4]
final class EdgeSAMEngine {
    private static let logger = Logger(subsystem: "com.imaiissatsu.BokeFocus", category: "EdgeSAM")
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
            Self.logger.info("Models loaded successfully")
        } else {
            Self.logger.info("Models not found — Vision-only mode")
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

        // Quality gate: reject if best mask has very low stability
        guard maskInfos[0].stability > 0.15 else { return nil }

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
            // Temperature=3.0 → balanced between picking winner and soft blending
            let w = exp((maskInfos[i].stability - maxStab) * 3.0)
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

        // Accumulate weighted logits using vDSP for vectorized performance
        let n = vDSP_Length(planeSize)
        for i in 0 ..< k {
            let srcOffset = maskInfos[i].index * planeSize
            var w = weights[i]
            // dst[j] += src[j] * w
            vDSP_vsma(masksPtr.advanced(by: srcOffset), 1, &w, dstPtr, 1, dstPtr, 1, n)
        }

        return result
    }

    // MARK: - Stability Score

    /// Compute stability score using vDSP for vectorized threshold counting.
    /// Stability = IoU(mask(t+offset), mask(t-offset))
    /// Uses vDSP_vthrsc to threshold without scalar loop.
    private func computeStabilityScore(
        logits: UnsafePointer<Float>,
        count: Int,
        threshold: Float,
        offset: Float
    ) -> Float {
        let n = vDSP_Length(count)

        // Shift logits by -highThresh, then clamp negative to 0, positive to 1
        var shifted = [Float](repeating: 0, count: count)
        var negHighThresh = -(threshold + offset)
        vDSP_vsadd(logits, 1, &negHighThresh, &shifted, 1, n)
        // Clamp: val > 0 → 1, val ≤ 0 → 0
        var lo: Float = 0
        var hi: Float = 1
        vDSP_vclip(shifted, 1, &lo, &hi, &shifted, 1, n)
        // ceil: any positive → 1 (already clipped to [0,1], but need 0.001→1)
        var highBinary = [Float](repeating: 0, count: count)
        for i in 0 ..< count { highBinary[i] = shifted[i] > 0 ? 1.0 : 0.0 }
        var highCount: Float = 0
        vDSP_sve(highBinary, 1, &highCount, n)

        // Same for low threshold
        var negLowThresh = -(threshold - offset)
        vDSP_vsadd(logits, 1, &negLowThresh, &shifted, 1, n)
        vDSP_vclip(shifted, 1, &lo, &hi, &shifted, 1, n)
        var lowBinary = [Float](repeating: 0, count: count)
        for i in 0 ..< count { lowBinary[i] = shifted[i] > 0 ? 1.0 : 0.0 }
        var lowCount: Float = 0
        vDSP_sve(lowBinary, 1, &lowCount, n)

        return lowCount > 0 ? highCount / lowCount : 0.0
    }
}
