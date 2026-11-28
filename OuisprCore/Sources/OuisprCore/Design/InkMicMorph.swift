// OuisprCore/Sources/OuisprCore/Design/InkMicMorph.swift
// The keyboard mic's three bars as strokes that can turn into ✓, ✕ and ^ ^.
import CoreGraphics
import Foundation

/// One stroke of ink with round caps, `width` thick: a straight line, or a curve bent
/// toward `control` (a quadratic Bézier; a straight stroke keeps its control at its middle).
///
/// A capsule is a stroke too: a bar `h` tall and `w` wide is the line between its two cap
/// centres, `h - w` long, drawn `w` thick. That is what lets the mic's bars and the ✓, ✕
/// and ^ ^ glyphs be the same four things in different places.
public struct InkStroke: Equatable, Sendable {
    public var start: CGPoint
    public var end: CGPoint
    public var width: CGFloat
    /// The point the stroke bends toward. Blending moves it like the ends, so a straight
    /// bar can spring into an arc and back.
    public var control: CGPoint

    public init(_ start: CGPoint, _ end: CGPoint, width: CGFloat) {
        self.init(start, end, bentToward: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), width: width)
    }

    public init(_ start: CGPoint, _ end: CGPoint, bentToward control: CGPoint, width: CGFloat) {
        self.start = start
        self.end = end
        self.width = width
        self.control = control
    }

    /// A stroke with no width: drawn as nothing, kept so every glyph has the same number
    /// of strokes and any two can be blended.
    static func hidden(at point: CGPoint) -> InkStroke {
        InkStroke(point, point, width: 0)
    }
}

/// The glyphs the keyboard mic turns into (lot 1.6, Alex's bench of 28 Nov 2026).
///
/// Every glyph is four strokes in the mic's own box: its centre is the origin, and one
/// unit is 1/24 of the box's side, the unit `InkMicBars` draws in. The order of the four
/// is what makes the morphs read: stroke 1 is the left bar, 2 the centre bar, 3 the right
/// bar, 4 a twin of the left bar.
///
/// - `.bars`: the logo, exactly as `InkMicBars` draws it.
/// - `.check`: ✓ Valider. The centre bar becomes the short stroke and the right bar the
///   long one, so the two bars on the right "form the tick" where the user tapped. The
///   left bar has gone to become the ✕, so strokes 1 and 4 are hidden at the tick's foot.
/// - `.smile`: ◠ ◠, the laughing eyes. Strokes 1 and 4 are the left eye, 2 and 3 the right,
///   each a quarter arc between the eye's foot and its top, so an eye is a half-moon with
///   a round top (lot 1.8, Alex: the ^ ^ were « trop pointus »). Its proportions are the
///   app's laughing eyes' (`InkGeometry.happyEye`): a radius of about 1.2 stroke widths,
///   0.95 of it in height.
/// - `.cross`: ✕ Annuler, in the cancel button's own box. Strokes 1 and 4 are its two
///   arms, both born from the left bar, so the bar "splits and turns" into the cross.
public enum InkMicGlyph: CaseIterable {
    case bars, check, smile, cross

    /// The ✓'s stroke, thicker than the ✕'s: it is the main action (bench choice).
    public static let checkWidth: CGFloat = 3.6
    /// The ✕'s stroke.
    public static let crossWidth: CGFloat = 2.8
    /// The ^ ^'s stroke, between the two: eyes, not an action.
    public static let smileWidth: CGFloat = 3.2

    /// The glyph's four strokes, in units of the mic's box (see the type).
    public var strokes: [InkStroke] {
        switch self {
        case .bars:
            return [Self.leftBar, Self.centreBar, Self.rightBar, Self.leftBar]
        case .check:
            let foot = CGPoint(x: -2.5, y: 5.5)
            return [
                .hidden(at: foot),
                InkStroke(CGPoint(x: -7, y: 0.5), foot, width: Self.checkWidth),
                InkStroke(foot, CGPoint(x: 7.5, y: -6.5), width: Self.checkWidth),
                .hidden(at: foot)
            ]
        case .smile:
            // Each stroke runs the way it did as a ^ ^, so the morphs keep their paths:
            // 1 and 2 rise from a foot to a top, 3 and 4 come down from a top to a foot.
            let left = Self.laughingEye(centre: -Self.smileCentreX), right = Self.laughingEye(centre: Self.smileCentreX)
            return [left.rising, right.rising, right.falling, left.falling]
        case .cross:
            return [
                InkStroke(CGPoint(x: -5.5, y: -5.5), CGPoint(x: 5.5, y: 5.5), width: Self.crossWidth),
                .hidden(at: .zero),
                .hidden(at: .zero),
                InkStroke(CGPoint(x: -5.5, y: 5.5), CGPoint(x: 5.5, y: -5.5), width: Self.crossWidth)
            ]
        }
    }

    /// `.bars` without its left bar (strokes 1 and 4 hidden where it stood): how the ✓
    /// starts on the listening screen, whose ✕ carries the left bar away.
    public static var barsWithoutLeft: [InkStroke] {
        var strokes = InkMicGlyph.bars.strokes
        strokes[0] = .hidden(at: leftBar.start)
        strokes[3] = .hidden(at: leftBar.start)
        return strokes
    }

    /// Only the left bar, twice (strokes 1 and 4), the others hidden: how the ✕ starts.
    public static var leftBarOnly: [InkStroke] {
        [leftBar, .hidden(at: .zero), .hidden(at: .zero), leftBar]
    }

    /// The laughing eye's radius, and where the two eyes sit, in the mic's units.
    static let smileRadius: CGFloat = 3.8
    static let smileCentreX: CGFloat = 6.2
    static let smileBaseline: CGFloat = 1.9

    /// One laughing eye: its left quarter rising to the top, its right quarter coming down.
    private static func laughingEye(centre: CGFloat) -> (rising: InkStroke, falling: InkStroke) {
        let top = CGPoint(x: centre, y: smileBaseline - 0.95 * smileRadius)
        let leftFoot = CGPoint(x: centre - smileRadius, y: smileBaseline)
        let rightFoot = CGPoint(x: centre + smileRadius, y: smileBaseline)
        // The control at the corner of the arc's box: the curve leaves the foot upright and
        // reaches the top level, so the two halves meet with no angle.
        return (
            InkStroke(leftFoot, top, bentToward: CGPoint(x: leftFoot.x, y: top.y), width: smileWidth),
            InkStroke(top, rightFoot, bentToward: CGPoint(x: rightFoot.x, y: top.y), width: smileWidth)
        )
    }

    // The bars of `InkMicBars`: 5 wide, 9 apart, 9.1, 21.3 and 13.7 tall, centred.
    static let leftBar = bar(x: -9, height: 9.1)
    static let centreBar = bar(x: 0, height: 21.3)
    static let rightBar = bar(x: 9, height: 13.7)

    private static func bar(x: CGFloat, height: CGFloat) -> InkStroke {
        let half = (height - 5) / 2
        return InkStroke(CGPoint(x: x, y: -half), CGPoint(x: x, y: half), width: 5)
    }
}

/// Strokes as one flat vector, so SwiftUI can spring from any glyph to any other.
///
/// Seven numbers a stroke (start x, start y, end x, end y, width, control x, control y). Vectors of different
/// lengths blend as if the shorter one were padded with zeros, which is what
/// `VectorArithmetic.zero` needs to be an empty vector.
public struct InkStrokeVector: Equatable, Sendable {
    public var values: [Double]

    public init(_ strokes: [InkStroke]) {
        var flat: [Double] = []
        flat.reserveCapacity(strokes.count * Self.stride)
        for stroke in strokes {
            flat.append(Double(stroke.start.x))
            flat.append(Double(stroke.start.y))
            flat.append(Double(stroke.end.x))
            flat.append(Double(stroke.end.y))
            flat.append(Double(stroke.width))
            flat.append(Double(stroke.control.x))
            flat.append(Double(stroke.control.y))
        }
        values = flat
    }

    /// Numbers per stroke.
    static let stride = 7

    init(values: [Double]) {
        self.values = values
    }

    /// The strokes back. A width the spring's overshoot pushed below zero draws nothing.
    public var strokes: [InkStroke] {
        // Split into typed steps: as one expression it timed out the type checker on CI.
        let whole: Int = values.count - values.count % Self.stride
        var result: [InkStroke] = []
        result.reserveCapacity(whole / Self.stride)
        var index: Int = 0
        while index < whole {
            let start = CGPoint(x: CGFloat(values[index]), y: CGFloat(values[index + 1]))
            let end = CGPoint(x: CGFloat(values[index + 2]), y: CGFloat(values[index + 3]))
            let width: CGFloat = CGFloat(Swift.max(0.0, values[index + 4]))
            let control = CGPoint(x: CGFloat(values[index + 5]), y: CGFloat(values[index + 6]))
            result.append(InkStroke(start, end, bentToward: control, width: width))
            index += Self.stride
        }
        return result
    }

    private static func combine(_ lhs: [Double], _ rhs: [Double], _ op: (Double, Double) -> Double) -> [Double] {
        let count = max(lhs.count, rhs.count)
        return (0..<count).map { index in
            op(index < lhs.count ? lhs[index] : 0, index < rhs.count ? rhs[index] : 0)
        }
    }
}

extension InkStrokeVector: AdditiveArithmetic {
    public static var zero: InkStrokeVector { InkStrokeVector(values: []) }

    public static func + (lhs: InkStrokeVector, rhs: InkStrokeVector) -> InkStrokeVector {
        InkStrokeVector(values: combine(lhs.values, rhs.values, +))
    }

    public static func - (lhs: InkStrokeVector, rhs: InkStrokeVector) -> InkStrokeVector {
        InkStrokeVector(values: combine(lhs.values, rhs.values, -))
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension InkStrokeVector: VectorArithmetic {
    public mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    public var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

/// The strokes, filled flat (never a gradient: the keyboard's 1.4 eyes, drawn with one,
/// did not show on device). Animating `strokes` springs every stroke from its place in one
/// glyph to its place in the next.
public struct InkStrokesShape: Shape {
    public var vector: InkStrokeVector

    public init(_ strokes: [InkStroke]) {
        vector = InkStrokeVector(strokes)
    }

    public var animatableData: InkStrokeVector {
        get { vector }
        set { vector = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        // The unit `InkMicBars` draws in: 1/24 of the box's shorter side.
        let unit = min(rect.width, rect.height) / 24
        var path = Path()
        for stroke in vector.strokes where stroke.width > 0.05 {
            var line = Path()
            line.move(to: CGPoint(x: rect.midX + stroke.start.x * unit, y: rect.midY + stroke.start.y * unit))
            line.addQuadCurve(
                to: CGPoint(x: rect.midX + stroke.end.x * unit, y: rect.midY + stroke.end.y * unit),
                control: CGPoint(x: rect.midX + stroke.control.x * unit, y: rect.midY + stroke.control.y * unit)
            )
            path.addPath(line.strokedPath(StrokeStyle(lineWidth: stroke.width * unit, lineCap: .round)))
        }
        return path
    }
}
#endif
