#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/InkFrameRenderer.swift
// Draws one frame of the ink character into a SwiftUI canvas.
import SwiftUI

/// How every surface paints an `InkFrame`: the app's character, the model preparation
/// eyes and the keyboard's listening eyes (lot 1.4).
///
/// WHY IN OUISPRCORE: the keyboard extension draws the same eyes as the app, in the same
/// ink, and two copies of the drawing would drift the first time one of them changed.
public enum InkFrameRenderer {

    /// Draws `frame` in a context already moved to the character's centre and scaled to
    /// its points.
    public static func draw(_ frame: InkFrame, in context: inout GraphicsContext) {
        // The logo's shading, in one ink: left .6, centre 1, right .8, faded in as the
        // stroke becomes the wave and out as it becomes eyes again.
        let ink = Color.ouisprInk
        let half = InkGeometry.halfLength
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: ink.opacity(1 - 0.4 * frame.shade), location: 0),
                .init(color: ink, location: 0.5),
                .init(color: ink.opacity(1 - 0.2 * frame.shade), location: 1)
            ]),
            startPoint: CGPoint(x: -half, y: 0),
            endPoint: CGPoint(x: half, y: 0)
        )

        for shape in frame.shapes {
            switch shape {
            case let .stroke(points, width):
                guard width > 0.2, let first = points.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x, y: first.y))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                // A stroke folded to one point still draws: a zero-length line with round
                // caps is a dot.
                if points.count == 1 { path.addLine(to: CGPoint(x: first.x, y: first.y)) }
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            case let .fill(outline):
                guard let first = outline.first else { continue }
                var path = Path()
                path.move(to: CGPoint(x: first.x, y: first.y))
                for point in outline.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                path.closeSubpath()
                context.fill(path, with: shading)
            }
        }
    }
}
#endif
