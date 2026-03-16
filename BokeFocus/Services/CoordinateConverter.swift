import CoreGraphics
import CoreML

final class CoordinateConverter {
    // MARK: - AspectFit display metrics

    struct DisplayMetrics {
        let displayWidth: CGFloat
        let displayHeight: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    func aspectFitMetrics(
        imageSize: CGSize, viewSize: CGSize
    ) -> DisplayMetrics {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        if imageAspect > viewAspect {
            let dw = viewSize.width
            let dh = viewSize.width / imageAspect
            return DisplayMetrics(
                displayWidth: dw, displayHeight: dh,
                offsetX: 0, offsetY: (viewSize.height - dh) / 2
            )
        } else {
            let dh = viewSize.height
            let dw = viewSize.height * imageAspect
            return DisplayMetrics(
                displayWidth: dw, displayHeight: dh,
                offsetX: (viewSize.width - dw) / 2, offsetY: 0
            )
        }
    }

    // MARK: - Screen → Image pixel

    func screenToImagePoint(
        screenPoint: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize
    ) -> CGPoint {
        let m = aspectFitMetrics(imageSize: imageSize, viewSize: viewSize)
        let imageX = (screenPoint.x - m.offsetX) * imageSize.width / m.displayWidth
        let imageY = (screenPoint.y - m.offsetY) * imageSize.height / m.displayHeight
        return CGPoint(x: imageX, y: imageY)
    }

    // MARK: - Screen → SAM 1024 space

    func screenToSAMCoords(
        screenPoint: CGPoint,
        viewSize: CGSize,
        params: LetterboxParams
    ) -> CGPoint {
        let m = aspectFitMetrics(
            imageSize: params.originalSize, viewSize: viewSize
        )
        let imageX = (screenPoint.x - m.offsetX) * params.originalSize.width / m.displayWidth
        let imageY = (screenPoint.y - m.offsetY) * params.originalSize.height / m.displayHeight

        let samX = imageX * params.scale + CGFloat(params.padX)
        let samY = imageY * params.scale + CGFloat(params.padY)

        // EdgeSAM uses (height, width) = (y, x) format
        return CGPoint(x: samY, y: samX)
    }

    // MARK: - BBox → SAM prompt (coords + labels MLMultiArray)

    func boundingBoxToSAMPrompt(
        startScreen: CGPoint,
        endScreen: CGPoint,
        viewSize: CGSize,
        params: LetterboxParams
    ) -> (coords: MLMultiArray, labels: MLMultiArray)? {
        // Normalize to ensure top-left / bottom-right regardless of drag direction
        let normalizedStart = CGPoint(
            x: min(startScreen.x, endScreen.x),
            y: min(startScreen.y, endScreen.y)
        )
        let normalizedEnd = CGPoint(
            x: max(startScreen.x, endScreen.x),
            y: max(startScreen.y, endScreen.y)
        )

        let topLeft = screenToSAMCoords(
            screenPoint: normalizedStart, viewSize: viewSize, params: params
        )
        let bottomRight = screenToSAMCoords(
            screenPoint: normalizedEnd, viewSize: viewSize, params: params
        )

        // coords shape: [1, 2, 2] — 2 points, each (h, w)
        guard let coords = try? MLMultiArray(
            shape: [1, 2, 2], dataType: .float32
        ) else { return nil }
        coords[[0, 0, 0] as [NSNumber]] = NSNumber(value: Float(topLeft.x))
        coords[[0, 0, 1] as [NSNumber]] = NSNumber(value: Float(topLeft.y))
        coords[[0, 1, 0] as [NSNumber]] = NSNumber(value: Float(bottomRight.x))
        coords[[0, 1, 1] as [NSNumber]] = NSNumber(value: Float(bottomRight.y))

        // labels: [2] = bbox top-left, [3] = bbox bottom-right
        guard let labels = try? MLMultiArray(
            shape: [1, 2], dataType: .float32
        ) else { return nil }
        labels[[0, 0] as [NSNumber]] = 2
        labels[[0, 1] as [NSNumber]] = 3

        return (coords, labels)
    }

    // MARK: - Points → SAM prompt (with optional bbox)

    func pointsToSAMPrompt(
        screenPoints: [(point: CGPoint, isPositive: Bool)],
        bboxStart: CGPoint?,
        bboxEnd: CGPoint?,
        viewSize: CGSize,
        params: LetterboxParams
    ) -> (coords: MLMultiArray, labels: MLMultiArray)? {
        var allPoints: [(CGPoint, Float)] = []

        // BBox points first
        if let start = bboxStart, let end = bboxEnd {
            let tl = screenToSAMCoords(
                screenPoint: start, viewSize: viewSize, params: params
            )
            let br = screenToSAMCoords(
                screenPoint: end, viewSize: viewSize, params: params
            )
            allPoints.append((tl, 2)) // bbox top-left
            allPoints.append((br, 3)) // bbox bottom-right
        }

        // Additional points
        for sp in screenPoints {
            let samPt = screenToSAMCoords(
                screenPoint: sp.point, viewSize: viewSize, params: params
            )
            allPoints.append((samPt, sp.isPositive ? 1 : 0))
        }

        guard !allPoints.isEmpty else { return nil }
        let count = allPoints.count

        guard let coords = try? MLMultiArray(
            shape: [1, NSNumber(value: count), 2], dataType: .float32
        ) else { return nil }

        guard let labels = try? MLMultiArray(
            shape: [1, NSNumber(value: count)], dataType: .float32
        ) else { return nil }

        for (i, (pt, label)) in allPoints.enumerated() {
            coords[[0, NSNumber(value: i), 0] as [NSNumber]] = NSNumber(value: Float(pt.x))
            coords[[0, NSNumber(value: i), 1] as [NSNumber]] = NSNumber(value: Float(pt.y))
            labels[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: label)
        }

        return (coords, labels)
    }
}
