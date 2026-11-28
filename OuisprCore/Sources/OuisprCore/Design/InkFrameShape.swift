#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/InkFrameShape.swift
// One frame of the ink character as a SwiftUI shape, for the keyboard (lot 1.8).
import SwiftUI

/// An `InkFrame` as one filled outline: strokes are turned into their outlines, fills
/// are kept. The keyboard fills it in flat ink, as it does every ink shape since the
/// 1.4 eyes (a `Canvas` with a gradient did not show on Alex's iPhone).
///
/// WHY: Alex, 28 Nov 2026, « l'onde du clavier est trop différente de celle de l'app ».
/// The keyboard now draws the app's own wave (`InkGeometry.wave` through an
/// `InkCharacterDriver`), at the app's size: `scale` 1 is the app's 200 pt character,
/// the wave about 108 pt wide in an 8 pt stroke.
public struct InkFrameShape: Shape {
    public let frame: InkFrame
    public let scale: CGFloat

    public init(_ frame: InkFrame, scale: CGFloat = 1) {
        self.frame = frame
        self.scale = scale
    }

    public func path(in rect: CGRect) -> Path {
        var outline = Path()
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        func place(_ point: InkPoint) -> CGPoint {
            CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y + CGFloat(point.y) * scale)
        }
        for shape in frame.shapes {
            switch shape {
            case let .stroke(points, width):
                guard width > 0.2, let first = points.first else { continue }
                var line = Path()
                line.move(to: place(first))
                for point in points.dropFirst() { line.addLine(to: place(point)) }
                if points.count == 1 { line.addLine(to: place(first)) }
                let style = StrokeStyle(lineWidth: CGFloat(width) * scale, lineCap: .round, lineJoin: .round)
                outline.addPath(line.strokedPath(style))
            case let .fill(points):
                guard let first = points.first else { continue }
                var area = Path()
                area.move(to: place(first))
                for point in points.dropFirst() { area.addLine(to: place(point)) }
                area.closeSubpath()
                outline.addPath(area)
            }
        }
        return outline
    }
}
#endif
