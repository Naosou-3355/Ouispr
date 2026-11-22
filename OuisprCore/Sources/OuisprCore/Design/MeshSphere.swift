// OuisprCore/Sources/OuisprCore/Design/MeshSphere.swift
// The maths of the mesh sphere (bench 5, V2): fine points on rings, lit on the rim.
import Foundation

/// The points of the mesh sphere and the rings they sit on.
///
/// WHY rings and not the Fibonacci lattice: bench 5 asked for the look of Alex's
/// reference image, a dense mesh whose rows of points read as fine threads. Points on
/// latitude rings give those rows, and the rings are what the wires are drawn along.
public struct MeshSphereGeometry: Sendable {
    /// Every point, ring after ring.
    public let points: [ParticleSpherePoint]
    /// The range of `points` each ring covers, from one pole to the other.
    public let rings: [Range<Int>]

    /// `ringCount` rings from pole to pole. A ring holds `pointsAtEquator` points at the
    /// equator and fewer toward the poles, so the spacing stays even.
    public init(ringCount: Int, pointsAtEquator: Int) {
        var points: [ParticleSpherePoint] = []
        var rings: [Range<Int>] = []
        for ring in 0..<max(ringCount, 0) {
            let theta = Double.pi * (Double(ring) + 0.5) / Double(ringCount)
            let ringRadius = sin(theta)
            let height = cos(theta)
            let count = max(6, Int((Double(pointsAtEquator) * ringRadius).rounded()))
            let start = points.count
            // Every other ring is shifted half a step, so the points do not line up in
            // columns, which would read as a grid.
            let shift = ring.isMultiple(of: 2) ? 0 : 0.5
            for index in 0..<count {
                let phi = 2 * Double.pi * (Double(index) + shift) / Double(count)
                points.append(ParticleSpherePoint(
                    x: cos(phi) * ringRadius,
                    y: height,
                    z: sin(phi) * ringRadius
                ))
            }
            rings.append(start..<points.count)
        }
        self.points = points
        self.rings = rings
    }

    /// The density of bench 5's "adjusted mesh": about 6,600 points.
    public static let standard = MeshSphereGeometry(ringCount: 52, pointsAtEquator: 200)
}

/// One point of a mesh frame, in the unit square: `x` and `y` run from 0 to 1 across
/// the view.
public struct MeshSphereVertex: Equatable, Sendable {
    public let x: Double
    public let y: Double
    /// 0 to 1.
    public let opacity: Double
    /// 0 where the surface faces the viewer, 1 on the silhouette.
    public let rim: Double
    /// 0 is the palette's first colour, 1 its last.
    public let mix: Double
}

/// A colour as red, green and blue from 0 to 1. Plain numbers, so the tests run
/// on the Mac without SwiftUI.
public struct MeshSphereRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
}

/// The values Alex picked on bench 5 (21 Nov 2026).
public enum MeshSphereStyle {
    /// The sphere's radius as a fraction of the view's side ("make it bigger": 0.36
    /// before). The rest is room for the relief.
    public static let radiusFraction = 0.40
    /// How far the silhouette bulges ("more marked").
    public static let relief = 0.16
    /// Blue, violet, then a touch of pink on the top edge.
    public static let paletteHex: [UInt] = [0x2F6BFF, 0x7C5CFF, 0xC855F0]
    /// A point's side as a fraction of the view's side ("too fine": 1.45 times V1).
    public static let dotFraction = 1.45 / 300
    /// A wire's width as a fraction of the view's side.
    public static let wireFraction = 1.0 / 420
    /// Below this opacity a wire segment is not drawn: the wires show on the rim only.
    public static let wireThreshold = 0.06
    /// The lean of the rings' axis, in radians: it puts the poles on the silhouette, so
    /// no "target" of rings faces the viewer.
    static let axisLean = -0.5
    /// The tilt toward the viewer, in radians.
    static let tilt = 0.12

    /// The palette colour `fraction` of the way along, as red, green and blue from 0
    /// to 1. In dark mode the brightest points (`opacityBand` near 1) are pushed
    /// toward a pale lilac, which is what makes the rim glow on a dark background.
    public static func rgb(at fraction: Double, opacityBand: Double, dark: Bool) -> MeshSphereRGB {
        let stops = paletteHex.map { hex in
            (Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF))
        }
        let clamped = min(max(fraction, 0), 1)
        let scaled = Double(stops.count - 1) * clamped
        let index = min(stops.count - 2, Int(scaled))
        let local = scaled - Double(index)
        let low = stops[index], high = stops[index + 1]
        var red = low.0 + (high.0 - low.0) * local
        var green = low.1 + (high.1 - low.1) * local
        var blue = low.2 + (high.2 - low.2) * local
        if !dark {
            // On a near-white background the lavender rim washed out (design loop,
            // 22 Nov 2026): the light palette is 30 % deeper.
            red *= 0.70
            green *= 0.70
            blue *= 0.70
        }
        if dark {
            let glow = max(0, (opacityBand - 0.55) / 0.4) * 0.55
            red += (235 - red) * glow
            green += (228 - green) * glow
            blue += (255 - blue) * glow
        }
        return MeshSphereRGB(red: red / 255, green: green / 255, blue: blue / 255)
    }
}

public extension ParticleSphereSimulation {
    /// The mesh points of the current frame.
    ///
    /// - Parameter dark: in dark mode the faces are a little brighter, because the
    ///   points are added to a dark background instead of laid on a light one.
    func meshVertices(
        geometry: MeshSphereGeometry,
        mood: ParticleSphereMood,
        reduceMotion: Bool,
        dark: Bool
    ) -> [MeshSphereVertex] {
        let drawnAngle = reduceMotion ? 0.6 : angle
        let drawnTime = reduceMotion ? 2.2 : time
        let cosAngle = cos(drawnAngle), sinAngle = sin(drawnAngle)
        let cosLean = cos(MeshSphereStyle.axisLean), sinLean = sin(MeshSphereStyle.axisLean)
        let cosTilt = cos(MeshSphereStyle.tilt), sinTilt = sin(MeshSphereStyle.tilt)

        let voice = reduceMotion ? 0 : level * current.voiceGain
        let breathing = sin(time * 3.2)
        let drawnScale = reduceMotion ? 1 : scale * (1 + 0.055 * current.pulse * breathing)
        // A loud voice deepens the bumps; the radius gives back what they add, so the
        // outermost bump never leaves the view (measured: 0.54 of the side without it).
        let radius = MeshSphereStyle.radiusFraction * drawnScale / (1 + 0.25 * voice)
        let lump = MeshSphereStyle.relief * (1 + 0.9 * voice)
        let ripple = reduceMotion ? 0.012 : current.ripple * (0.012 + 0.05 * voice)
        let brightness = Self.meshBrightness(mood: mood, voice: level, breathing: breathing, reduceMotion: reduceMotion)
        let frontBase = dark ? 0.24 : 0.16
        let t = drawnTime

        return geometry.points.map { point in
            let px = point.x, py = point.y, pz = point.z
            // A slow organic swell in the sphere's own space, so the bumps turn with it,
            // plus a fast ripple that the voice feeds.
            let swell = 0.55 * sin(2.3 * px + 1.7 * py + t * 0.55) * sin(2.1 * pz - 1.3 * py + t * 0.37)
                + 0.30 * sin(4.3 * py + 3.1 * pz - t * 0.8)
                + 0.15 * sin(6.7 * px - 5.3 * py + t * 1.1)
            let wave = sin(5.5 * px + 4.5 * py + t * 3.2) * sin(5 * pz - 3.5 * px + t * 2.7)
            let distance = 1 + lump * swell + ripple * wave

            // Turn around the rings' axis, lean that axis sideways, tilt toward the viewer.
            let turnedX = (px * cosAngle + pz * sinAngle) * distance
            let turnedZ = (-px * sinAngle + pz * cosAngle) * distance
            let turnedY = py * distance
            let x = turnedX * cosLean - turnedY * sinLean
            let y = turnedX * sinLean + turnedY * cosLean
            let screenY = y * cosTilt - turnedZ * sinTilt
            let depth = y * sinTilt + turnedZ * cosTilt

            // Fresnel-like: bright where the surface turns away, faint where it faces you.
            let facing = abs(depth) / max(distance, 0.001)
            let rim = (1 - min(facing, 1)) * (1 - min(facing, 1))
            let opacity = depth > 0 ? frontBase + (1 - frontBase) * rim : 0.06 + 0.5 * rim

            return MeshSphereVertex(
                x: 0.5 + x * radius,
                y: 0.5 + screenY * radius,
                opacity: min(max(opacity * brightness, 0), 1),
                rim: rim,
                // Bottom left to top right.
                mix: min(max(0.5 + 0.48 * (x - screenY) / 1.15, 0), 1)
            )
        }
    }

    /// With Reduce Motion the brightness carries what the motion no longer does.
    private static func meshBrightness(
        mood: ParticleSphereMood,
        voice: Double,
        breathing: Double,
        reduceMotion: Bool
    ) -> Double {
        guard reduceMotion else { return 1 }
        switch mood {
        case .listening:
            return 0.55 + 0.45 * voice
        case .working:
            // Held, not breathing: under Reduce Motion no loop runs (audit, 22 Nov
            // 2026, finding 14). Dimmer than at rest; the stage label says the rest.
            return 0.81
        case .resting, .done:
            return 1
        }
    }
}
