// OuisprCore/Sources/OuisprCore/Design/InkPreparationEyes.swift
// The ink character on the model preparation screen: its two eyes, and how full eyes
// come alive as laughing ones.
import Foundation

/// The model preparation screen's face (lot 1.1, Alex's bench of 27 Nov 2026, « Les yeux
/// se remplissent »): the ink character's resting eyes, at the character's own sizes,
/// drawn as outlines that the ink fills from the bottom as the preparation runs. When the
/// model is ready they come alive as the laughing eyes the end of a dictation shows.
public extension InkGeometry {

    /// The centre of the right eye, in the character's space (the left one is mirrored).
    static var eyeCentre: InkPoint { InkPoint(eyeX, eyeY) }

    /// Half the length of an eye's stroke, between its two round caps.
    static var eyeStrokeHalfLength: Double { eyeHalfHeight }

    /// Full eyes → laughing eyes (« ils prennent vie »). Alex asked for the passage
    /// between the two to be fluid, not a cross-fade: each full capsule squashes up into
    /// a dot at the top of its future arc, and the arc unrolls from there to both sides.
    ///
    /// WHY THIS SHAPE: it is `wake`, the way back from laughing eyes to rest at the end of
    /// a dictation, played the other way and without its pop, so the two read as the same
    /// gesture. Every frame is a drawable stroke or ribbon of the same ink, and the dot in
    /// the middle is as wide as both the stroke before it and the arc after it, so nothing
    /// jumps there.
    ///
    /// - Parameter tau: 0 for the full resting eyes, 1 for `held(.done)`'s eyes. The view
    ///   drives it with a spring that does not overshoot.
    static func brighten(_ tau: Double) -> InkFrame {
        let t = clamp01(tau)
        let baseline = eyeY + 3, top = baseline - happyRadius * 0.95
        if t < 0.5 {
            let k = inOut(t / 0.5)
            return InkFrame(shapes: [-1.0, 1].map { side in
                let x = side * eyeX, y = lerp(eyeY, top, k), half = eyeHalfHeight * (1 - k)
                return .stroke(
                    points: [InkPoint(x, y - half), InkPoint(x, y + half)],
                    width: lerp(eyeWidth, strokeWidth, k)
                )
            }, shade: 0)
        }
        let spread = inOut((t - 0.5) / 0.5), count = 22
        let shapes: [InkShape] = [-1.0, 1].map { side in
            let points = (0..<count).map { j -> InkPoint in
                let s = 0.5 + (Double(j) / Double(count - 1) - 0.5) * spread, angle = Double.pi * (1 - s)
                return InkPoint(side * (eyeX - happyRadius * cos(angle)), baseline - happyRadius * 0.95 * sin(.pi * s))
            }
            return .fill(outline: ribbon(points, halfWidths: points.map { _ in strokeWidth / 2 }, startCap: true, endCap: true))
        }
        return InkFrame(shapes: shapes, shade: smoothstep(0, 1, spread))
    }
}
