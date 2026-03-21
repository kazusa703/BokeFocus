import CoreImage
import os
import UIKit
import Vision

final class VisionEngine {
    private static let logger = Logger(subsystem: "com.imaiissatsu.BokeFocus", category: "Vision")
    func detectForeground(image: CIImage, tapPoint: CGPoint) async -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)

        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("Vision request failed: \(error.localizedDescription)")
            return nil
        }

        guard let result = request.results?.first else { return nil }

        let instanceMask = result.instanceMask
        let tappedInstance = readPixelValueWithSearch(
            mask: instanceMask,
            at: tapPoint,
            imageSize: image.extent.size
        )

        guard tappedInstance > 0 else { return nil }

        do {
            let scaledMask = try result.generateScaledMaskForImage(
                forInstances: IndexSet(integer: Int(tappedInstance)),
                from: handler
            )
            return CIImage(cvPixelBuffer: scaledMask)
        } catch {
            Self.logger.error("Mask generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Read pixel with rounding, then search nearby if tap lands on background
    private func readPixelValueWithSearch(
        mask: CVPixelBuffer,
        at point: CGPoint,
        imageSize: CGSize
    ) -> UInt8 {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Use rounding instead of truncation for better precision
        let maskX = Int((point.x * CGFloat(width) / imageSize.width).rounded())
        let maskY = Int((point.y * CGFloat(height) / imageSize.height).rounded())

        // Check exact tap point first
        if let value = safeRead(ptr: ptr, x: maskX, y: maskY,
                                width: width, height: height, bytesPerRow: bytesPerRow),
           value > 0 {
            return value
        }

        // Search in expanding radius (up to 5px in mask space) for nearest instance
        // Helps when user taps slightly outside the detected boundary
        for radius in 1 ... 5 {
            for dy in -radius ... radius {
                for dx in -radius ... radius {
                    guard abs(dx) == radius || abs(dy) == radius else { continue }
                    if let value = safeRead(ptr: ptr, x: maskX + dx, y: maskY + dy,
                                            width: width, height: height, bytesPerRow: bytesPerRow),
                       value > 0 {
                        return value
                    }
                }
            }
        }

        return 0
    }

    private func safeRead(
        ptr: UnsafePointer<UInt8>, x: Int, y: Int,
        width: Int, height: Int, bytesPerRow: Int
    ) -> UInt8? {
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        return ptr[y * bytesPerRow + x]
    }
}
