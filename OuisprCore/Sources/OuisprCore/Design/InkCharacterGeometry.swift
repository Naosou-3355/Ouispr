// OuisprCore/Sources/OuisprCore/Design/InkCharacterGeometry.swift
// The ink character's shapes: its held states and every passage between them.
import Foundation

/// A point in the character's own space: points, origin at its centre, y down.
public struct InkPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// One piece of ink: a round-capped stroke, or a filled outline for the liquid moments
/// (the neck of the drop, the smiling eyes), whose width changes along their length.
public enum InkShape: Equatable, Sendable {
    case stroke(points: [InkPoint], width: Double)
    case fill(outline: [InkPoint])
}

/// What to draw on one frame.
public struct InkFrame: Equatable, Sendable {
    public var shapes: [InkShape]
    /// How much of the logo's shading the stroke carries: 0 for one even ink (the
    /// eyes), 1 for the logo's left .6 / centre 1 / right .8 opacities.
    public var shade: Double

    public init(shapes: [InkShape], shade: Double) {
        self.shapes = shapes
        self.shade = shade
    }
}

/// The moving inputs the shapes read: the three ondulation levels, the glide of the
/// crests and the clock of the processing breath.
public struct InkPose: Equatable, Sendable {
    public var levels: [Double]
    public var phase: Double
    public var clock: Double

    public init(levels: [Double], phase: Double, clock: Double) {
        self.levels = levels
        self.phase = phase
        self.clock = clock
    }

    /// The wave at its resting height, with no glide.
    public static let still = InkPose(levels: InkGeometry.baseHeights.map { $0 / 42 * 0.5 }, phase: 0, clock: 0)
}

/// The character chosen on Alex's benches of 24 Nov 2026: one ink stroke that is two
/// eyes at rest, the logo's wave while it listens, one breathing crest while it works,
/// and two laughing eyes when it is done. A line-for-line port of the bench
/// (`depart/scene.js`, variants « arche », « lente », « nette », « yeux rieurs »).
///
/// WHY one stroke travelling along a path rather than shapes that fade into each
/// other: Alex asked for studio-style continuity with no fade and no blur. Every
/// passage is the same ink moving (Disney's arcs, anticipation, squash and stretch,
/// follow-through), so any frame of any passage is a drawable stroke.
///
/// Sizes are in points for a 240 pt frame, the size the bench validated (wave 107 pt
/// wide, stroke 8 pt); the view scales them to its frame.
public enum InkGeometry {
    // The bench's scene units, kept so every number below reads as it did there.
    private static let unit = 180.0
    private static let benchScale = 64.0 / 48
    private static let ondulationScale = benchScale * 107 / 86

    /// The wave's stroke: 8 pt.
    public static let strokeWidth = 6 * benchScale
    /// One ondulation's width.
    static let period = 11 * ondulationScale
    static let lobeSpread = 6 * ondulationScale
    /// Half the wave's width: the wave is about 107 pt wide.
    public static let halfLength = 2.95 * period
    /// The eyes: capsules 9.7 pt wide, 18 pt tall, 38 pt apart.
    static let eyeX = 0.105 * unit
    public static let eyeWidth = 2 * 0.027 * unit
    static let eyeHalfHeight = 0.05 * unit
    static let eyeY = -0.02 * unit
    /// The radius of a laughing eye's arc.
    static let happyRadius = 9.5
    /// The logo's three bars, 18 / 42 / 27: the heights of the middle ondulations.
    public static let baseHeights = [18.0, 42, 27]
    /// How far the gaze moves the eyes, per unit of gaze.
    static let gazeReach = 0.16 * unit

    /// The drop « nette »: neck spread, the moment it breaks, the recoil's damping.
    static let dropNeckSpread = 5.0
    public static let dropBreak = 0.42
    static let dropRecoilDamping = 0.38
    public static let dropDuration = 0.8
    /// Seconds from the drop's start to the moment the bridge breaks: when Home's new
    /// card leaves the character.
    public static var dropBreakTime: Double { dropBreak * dropDuration }

    // MARK: - Held states

    /// The wave while listening: five ondulations, the middle three as tall as the
    /// logo's bars and following the voice, the crests gliding.
    public static func wave(_ x: Double, _ pose: InkPose) -> Double {
        let heights = (0..<3).map { 0.42 * max(9 * ondulationScale, 42 * ondulationScale * max(0, pose.levels[$0])) }
        let glide = pose.phase * period * 2
        let lobes = [
            (-2 * period, 0.45 * heights[0]), (-period, heights[0]), (0, heights[1]),
            (period, heights[2]), (2 * period, 0.45 * heights[2])
        ]
        var envelope = 0.0
        for (centre, height) in lobes {
            envelope += height * exp(-pow((x - centre) / lobeSpread, 2))
        }
        envelope *= 1 - smoothstep(2.3 * period, 2.75 * period, abs(x))
        return -envelope * cos(.pi * (x - glide) / period)
    }

    /// Processing: one crest breathing in the centre, slowly (1.6 s).
    public static func bump(_ x: Double, _ pose: InkPose) -> Double {
        let breath = 0.5 - 0.5 * cos(2 * .pi * pose.clock / 1.6)
        return -(5 + 7 * breath) * exp(-pow(x / (1.1 * period), 2))
    }

    static func line(_ half: Double, count: Int = 64, _ height: (Double) -> Double) -> [InkPoint] {
        (0..<count).map { j in
            let x = -half + 2 * half * Double(j) / Double(count - 1)
            return InkPoint(x, height(x))
        }
    }

    static func eyes(gazeX: Double, gazeY: Double, blink: Double) -> [InkShape] {
        let half = eyeHalfHeight * (1 - blink)
        return [-1.0, 1].map { side in
            let x = side * eyeX + gazeX * gazeReach, y = eyeY - gazeY * gazeReach
            return .stroke(points: [InkPoint(x, y - half), InkPoint(x, y + half)], width: eyeWidth)
        }
    }

    /// A held state: rest (two eyes), listening (the wave), working (the crest), done
    /// (two laughing eyes).
    public static func held(
        _ mood: ParticleSphereMood,
        pose: InkPose,
        gazeX: Double = 0,
        gazeY: Double = 0,
        blink: Double = 0
    ) -> InkFrame {
        switch mood {
        case .resting:
            return InkFrame(shapes: eyes(gazeX: gazeX, gazeY: gazeY, blink: blink), shade: 0)
        case .listening:
            return InkFrame(shapes: [.stroke(points: line(halfLength) { wave($0, pose) }, width: strokeWidth)], shade: 1)
        case .working:
            return InkFrame(shapes: [.stroke(points: line(0.6 * halfLength) { bump($0, pose) }, width: strokeWidth)], shade: 1)
        case .done:
            return InkFrame(shapes: [-1.0, 1].map { .fill(outline: happyEye(side: $0, recoil: 1, bend: 1)) }, shade: 1)
        }
    }

    // MARK: - Passages

    /// Rest → listening (« Les yeux s'ouvrent en arche », 0.9 s): the eyes squash into
    /// dots leaning in, part to their own side, rise and meet at the top as an arch;
    /// the arch settles into the line, centre first.
    ///
    /// Played backwards it is the way back to rest from a cancelled dictation, so the
    /// line it settles into is a parameter: the wave, or the processing crest.
    public static func arch(
        _ tau: Double,
        gazeX: Double,
        gazeY: Double,
        lineHalf: Double = halfLength,
        line height: (Double) -> Double
    ) -> InkFrame {
        let split = 0.55, radiusX = 40.0, radiusY = 30.0
        let y = eyeY - gazeY * gazeReach * (1 - tau), dx = gazeX * gazeReach * (1 - tau), top = y - 6
        func side(_ s: Double) -> [InkPoint] {
            let start = InkPoint(s * eyeX + dx, y), shoulder = InkPoint(s * radiusX, top)
            var points = [start]
            cubic([start, InkPoint(start.x + s * 8, start.y), InkPoint(shoulder.x, shoulder.y + 8), shoulder], count: 8, into: &points)
            for j in 1...20 {
                let angle = Double.pi / 2 * Double(j) / 20
                points.append(InkPoint(s * radiusX * cos(angle), top - radiusY * sin(angle)))
            }
            return points
        }
        if tau < split {
            let ta = tau / split
            if ta < 0.2 {
                // Anticipation: the eyes squash into dots and lean in a little.
                let k = ta / 0.2, half = eyeHalfHeight * (1 - inOut(k)), nudge = 1.5 * sin(.pi * k)
                return InkFrame(shapes: [-1.0, 1].map { s in
                    let x = s * (eyeX - nudge) + dx
                    return .stroke(points: [InkPoint(x, y - half), InkPoint(x, y + half)], width: eyeWidth)
                }, shade: 0)
            }
            let tb = (ta - 0.2) / 0.8
            return InkFrame(shapes: [-1.0, 1].map { s in
                let points = side(s), lengths = cumulativeLengths(points)
                let total = lengths[lengths.count - 1], quarter = total - lengths[8]
                let head = total * inOut(tb), length = min(head, quarter * pow(smoothstep(0.05, 1, tb), 1.15)), tail = head - length
                let speed = min(1, abs(inOut(tb + 0.01) - inOut(tb)) / 0.01 / 1.5)
                return .stroke(
                    points: subPolyline(points, lengths, from: tail, to: max(head, tail + 0.01), count: 36),
                    width: lerp(eyeWidth, strokeWidth, smoothstep(0, 0.4, tb)) * (1 - 0.12 * speed)
                )
            }, shade: 0)
        }
        // The arch (left foot, top, right foot) settles into the line, the centre first.
        let tb = (tau - split) / (1 - split), count = 72
        var archPoints: [InkPoint] = []
        for j in 0...40 {
            let angle = Double.pi * (1 - Double(j) / 40)
            archPoints.append(InkPoint(radiusX * cos(angle), top - radiusY * sin(angle)))
        }
        let archLengths = cumulativeLengths(archPoints)
        let along = subPolyline(archPoints, archLengths, from: 0, to: archLengths[archLengths.count - 1], count: count)
        let points = (0..<count).map { j -> InkPoint in
            let u = -1 + 2 * Double(j) / Double(count - 1), x = u * lineHalf, k = inOut((tb - 0.3 * abs(u)) / 0.7)
            return InkPoint(lerp(along[j].x, x, k), lerp(along[j].y, height(x), k))
        }
        return InkFrame(shapes: [.stroke(points: points, width: strokeWidth)], shade: smoothstep(0, 0.8, tb))
    }

    /// Listening → working (0.7 s): the wave dies out from its ends inward while the
    /// stroke tightens, leaving one crest breathing.
    public static func calm(_ tau: Double, pose: InkPose) -> InkFrame {
        let half = lerp(halfLength, 0.6 * halfLength, inOut(tau))
        let points = line(half) { x in
            let k = smoothstep(0, 1, 1.5 * tau - 0.5 * (1 - abs(x) / halfLength))
            return lerp(wave(x, pose), bump(x, pose), k)
        }
        return InkFrame(shapes: [.stroke(points: points, width: strokeWidth)], shade: 1)
    }

    /// Working → done (drop « nette », 0.8 s, « yeux rieurs »): the stroke flattens,
    /// stretches and necks into a liquid bridge; the bridge breaks, each half snaps
    /// back and curls up into a raised arc, an eye that laughs.
    public static func drop(_ tau: Double, pose: InkPose) -> InkFrame {
        if tau < dropBreak {
            let flat = 1 - inOut(tau / 0.3)
            let reach = tau < 0.3
                ? lerp(0.6 * halfLength, eyeX + 2, inOut(tau / 0.3))
                : lerp(eyeX + 2, eyeX + 8, inOut((tau - 0.3) / (dropBreak - 0.3)))
            let neck = pow(clamp01((tau - 0.2) / (dropBreak - 0.2)), 1.6)
            return InkFrame(shapes: [.fill(outline: bridge(reach: reach, neck: neck) { flat * bump($0, pose) })], shade: 1)
        }
        let elapsed = (tau - dropBreak) * dropDuration
        let recoil = springStep(elapsed, response: 0.3, damping: dropRecoilDamping)
        let tip = lerp(0, eyeX - happyRadius, recoil), reach = lerp(eyeX + 8, eyeX + happyRadius, clamp01(recoil))
        let taper = lerp(dropNeckSpread, strokeWidth * 0.45, clamp01(recoil))
        let bend = springStep(elapsed - 0.08, response: 0.32, damping: 0.7)
        return InkFrame(shapes: [-1.0, 1].map {
            .fill(outline: happyEye(side: $0, recoil: recoil, bend: bend, tip: tip, reach: reach, taper: taper))
        }, shade: 1)
    }

    /// Done → rest (0.55 s): each arc closes up to its top, then stands up as an eye
    /// with a soft pop.
    public static func wake(_ tau: Double) -> InkFrame {
        if tau < 0.5 {
            let spread = 1 - inOut(tau / 0.5), count = 22, baseline = eyeY + 3
            let shapes: [InkShape] = [-1.0, 1].map { side in
                let points = (0..<count).map { j -> InkPoint in
                    let s = 0.5 + (Double(j) / Double(count - 1) - 0.5) * spread, angle = Double.pi * (1 - s)
                    return InkPoint(side * (eyeX - happyRadius * cos(angle)), baseline - happyRadius * 0.95 * sin(.pi * s))
                }
                return .fill(outline: ribbon(points, halfWidths: points.map { _ in strokeWidth / 2 }, startCap: true, endCap: true))
            }
            return InkFrame(shapes: shapes, shade: 1 - smoothstep(0.2, 1, tau))
        }
        let k = springStep((tau - 0.5) / 0.5 * 0.35, response: 0.22, damping: 0.75)
        let top = eyeY + 3 - happyRadius * 0.95
        return InkFrame(shapes: [-1.0, 1].map { side in
            let x = side * eyeX, y = lerp(top, eyeY, smoothstep(0, 0.6, k)), half = eyeHalfHeight * k
            return .stroke(points: [InkPoint(x, y - half), InkPoint(x, y + half)], width: lerp(strokeWidth, eyeWidth, clamp01(k)))
        }, shade: 0)
    }

    // MARK: - Liquid shapes

    /// A filled outline around a centre line, with its own half-width at every point
    /// and optional round caps.
    static func ribbon(_ points: [InkPoint], halfWidths: [Double], startCap: Bool, endCap: Bool) -> [InkPoint] {
        let count = points.count
        var left: [InkPoint] = [], right: [InkPoint] = [], tangents: [InkPoint] = []
        for k in 0..<count {
            let a = points[max(0, k - 1)], b = points[min(count - 1, k + 1)]
            var tx = b.x - a.x, ty = b.y - a.y
            var length = hypot(tx, ty)
            if length < 1e-6 { tx = 1; ty = 0; length = 1 }
            tx /= length; ty /= length
            tangents.append(InkPoint(tx, ty))
            left.append(InkPoint(points[k].x - ty * halfWidths[k], points[k].y + tx * halfWidths[k]))
            right.append(InkPoint(points[k].x + ty * halfWidths[k], points[k].y - tx * halfWidths[k]))
        }
        func cap(_ p: InkPoint, _ t: InkPoint, _ h: Double, back: Bool) -> [InkPoint] {
            let nx = -t.y, ny = t.x
            return (1..<8).map { j in
                let angle = Double.pi * Double(j) / 8, c = cos(angle), s = sin(angle)
                return back
                    ? InkPoint(p.x - h * nx * c - h * t.x * s, p.y - h * ny * c - h * t.y * s)
                    : InkPoint(p.x + h * (nx * c + t.x * s), p.y + h * (ny * c + t.y * s))
            }
        }
        var outline = left
        if endCap { outline += cap(points[count - 1], tangents[count - 1], halfWidths[count - 1], back: false) }
        outline += right.reversed()
        if startCap { outline += cap(points[0], tangents[0], halfWidths[0], back: true) }
        return outline
    }

    /// Before the break: one shape whose middle narrows into a neck.
    static func bridge(reach: Double, neck: Double, count: Int = 44, _ height: (Double) -> Double) -> [InkPoint] {
        var points: [InkPoint] = [], widths: [Double] = []
        for j in 0..<count {
            let x = -reach + 2 * reach * Double(j) / Double(count - 1)
            points.append(InkPoint(x, height(x)))
            widths.append(strokeWidth / 2 * (1 - neck * exp(-pow(x / dropNeckSpread, 2))))
        }
        return ribbon(points, halfWidths: widths, startCap: true, endCap: true)
    }

    /// The width along a half after the break: zero at the torn tip, full a little further.
    static func halfWidths(length: Double, taper: Double, count: Int) -> [Double] {
        (0..<count).map { j in
            let d = length * Double(j) / Double(count - 1)
            return strokeWidth / 2 * (1 - exp(-pow(d / taper, 2)))
        }
    }

    /// A half bending into a raised arc, the eye that laughs: inner end tapered, outer
    /// end round; once snapped back, the torn tip rounds off too.
    static func happyEye(
        side: Double,
        recoil: Double,
        bend: Double,
        tip: Double = eyeX - happyRadius,
        reach: Double = eyeX + happyRadius,
        taper: Double = strokeWidth * 0.45
    ) -> [InkPoint] {
        let count = 22, baseline = eyeY + 3
        let points = (0..<count).map { j -> InkPoint in
            let s = Double(j) / Double(count - 1), along = side * lerp(tip, reach, s), angle = Double.pi * (1 - s)
            let arcX = side * (eyeX - happyRadius * cos(angle)), arcY = baseline - happyRadius * 0.95 * sin(.pi * s)
            return InkPoint(lerp(along, arcX, bend), lerp(0, arcY, bend))
        }
        let floor = strokeWidth / 2 * smoothstep(0.4, 1, recoil)
        let widths = halfWidths(length: abs(reach - tip), taper: taper, count: count).map { max($0, floor) }
        return ribbon(points, halfWidths: widths, startCap: true, endCap: true)
    }

    // MARK: - Polylines: a stroke is a window travelling along a path

    static func cumulativeLengths(_ points: [InkPoint]) -> [Double] {
        var lengths = [0.0]
        for k in 1..<points.count {
            lengths.append(lengths[k - 1] + hypot(points[k].x - points[k - 1].x, points[k].y - points[k - 1].y))
        }
        return lengths
    }

    static func subPolyline(_ points: [InkPoint], _ lengths: [Double], from a: Double, to b: Double, count: Int) -> [InkPoint] {
        var out: [InkPoint] = [], k = 1
        for j in 0..<count {
            let s = a + (b - a) * Double(j) / Double(count - 1)
            while k < lengths.count - 1 && lengths[k] < s { k += 1 }
            let s0 = lengths[k - 1], s1 = lengths[k], f = s1 > s0 ? clamp01((s - s0) / (s1 - s0)) : 0
            out.append(InkPoint(lerp(points[k - 1].x, points[k].x, f), lerp(points[k - 1].y, points[k].y, f)))
        }
        return out
    }

    static func cubic(_ c: [InkPoint], count: Int, into out: inout [InkPoint]) {
        let p0 = c[0], p1 = c[1], p2 = c[2], p3 = c[3]
        for j in 1...count {
            let t = Double(j) / Double(count), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            out.append(InkPoint(a * p0.x + b * p1.x + c * p2.x + d * p3.x, a * p0.y + b * p1.y + c * p2.y + d * p3.y))
        }
    }
}

// MARK: - Easing

func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

/// Cubic in-out: slow in, slow out.
func inOut(_ x: Double) -> Double {
    let t = clamp01(x)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

/// The step response of a spring released at `t` = 0: 0 → 1, overshooting when
/// `damping` is under 1. `response` is the period in seconds (Apple's model, WWDC23).
func springStep(_ t: Double, response: Double, damping: Double) -> Double {
    if t <= 0 { return 0 }
    let omega = 2 * Double.pi / response
    if damping >= 1 { return 1 - exp(-omega * t) * (1 + omega * t) }
    let root = sqrt(1 - damping * damping), damped = omega * root
    return 1 - exp(-damping * omega * t) * (cos(damped * t) + damping / root * sin(damped * t))
}
