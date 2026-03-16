import CoreImage
import UIKit
import Vision

final class VisionEngine {
    func detectForeground(image: CIImage, tapPoint: CGPoint) async -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)

        do {
            try handler.perform([request])
        } catch {
            print("Vision request failed: \(error)")
            return nil
        }

        guard let result = request.results?.first else { return nil }

        let instanceMask = result.instanceMask
        let tappedInstance = readPixelValue(
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
            print("Mask generation failed: \(error)")
            return nil
        }
    }

    private func readPixelValue(
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

        // Convert image coordinates to mask coordinates
        let maskX = Int(point.x * CGFloat(width) / imageSize.width)
        let maskY = Int(point.y * CGFloat(height) / imageSize.height)

        guard maskX >= 0, maskX < width, maskY >= 0, maskY < height else { return 0 }

        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
        return ptr[maskY * bytesPerRow + maskX]
    }
}
