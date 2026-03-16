import SwiftUI

struct SelectionOverlayView: View {
    let points: [(point: CGPoint, isPositive: Bool)]
    let bboxStart: CGPoint?
    let bboxEnd: CGPoint?
    let isDragging: Bool
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        Canvas { context, _ in
            // Draw BBox with animated dashes
            if let start = bboxStart, let end = bboxEnd {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )

                // Animated dashed outline
                context.stroke(
                    Path(rect),
                    with: .color(.yellow),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: [8, 4],
                        dashPhase: dashPhase
                    )
                )

                if isDragging {
                    context.fill(
                        Path(rect),
                        with: .color(.yellow.opacity(0.1))
                    )

                    // Corner handles
                    let corners = [
                        CGPoint(x: rect.minX, y: rect.minY),
                        CGPoint(x: rect.maxX, y: rect.minY),
                        CGPoint(x: rect.minX, y: rect.maxY),
                        CGPoint(x: rect.maxX, y: rect.maxY),
                    ]
                    for corner in corners {
                        let handle = Path(ellipseIn: CGRect(
                            x: corner.x - 5, y: corner.y - 5,
                            width: 10, height: 10
                        ))
                        context.fill(handle, with: .color(.yellow))
                        context.stroke(handle, with: .color(.white), lineWidth: 1.5)
                    }
                }
            }

            // Draw points with larger indicators
            for pt in points {
                let color: Color = pt.isPositive ? .green : .red
                let center = pt.point
                let outerRadius: CGFloat = 11
                let innerRadius: CGFloat = 4

                // Outer ring
                let outerCircle = Path(ellipseIn: CGRect(
                    x: center.x - outerRadius,
                    y: center.y - outerRadius,
                    width: outerRadius * 2,
                    height: outerRadius * 2
                ))
                context.fill(outerCircle, with: .color(color.opacity(0.8)))
                context.stroke(outerCircle, with: .color(.white), lineWidth: 2)

                // Inner dot for precise position
                let innerCircle = Path(ellipseIn: CGRect(
                    x: center.x - innerRadius,
                    y: center.y - innerRadius,
                    width: innerRadius * 2,
                    height: innerRadius * 2
                ))
                context.fill(innerCircle, with: .color(.white))

                // + or - symbol
                let symbolSize: CGFloat = 6
                if pt.isPositive {
                    // Plus
                    var hLine = Path()
                    hLine.move(to: CGPoint(x: center.x - symbolSize, y: center.y))
                    hLine.addLine(to: CGPoint(x: center.x + symbolSize, y: center.y))
                    var vLine = Path()
                    vLine.move(to: CGPoint(x: center.x, y: center.y - symbolSize))
                    vLine.addLine(to: CGPoint(x: center.x, y: center.y + symbolSize))
                    context.stroke(hLine, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
                    context.stroke(vLine, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
                } else {
                    // Minus
                    var hLine = Path()
                    hLine.move(to: CGPoint(x: center.x - symbolSize, y: center.y))
                    hLine.addLine(to: CGPoint(x: center.x + symbolSize, y: center.y))
                    context.stroke(hLine, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                dashPhase = 12
            }
        }
    }
}
