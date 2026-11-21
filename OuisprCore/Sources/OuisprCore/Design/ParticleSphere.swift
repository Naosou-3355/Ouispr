// OuisprCore/Sources/OuisprCore/Design/ParticleSphere.swift
// The maths of the particle sphere: where its points sit, how it moves, what a frame holds.
import Foundation

/// One point on the unit sphere.
public struct ParticleSpherePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// What the sphere is saying. One per stage of a dictation.
public enum ParticleSphereMood: Equatable, Sendable {
    /// Nothing is happening: the sphere turns on its own.
    case resting
    /// The microphone is open: the surface follows the voice.
    case listening
    /// The text is being transcribed or cleaned up: the sphere breathes.
    case working
    /// The text is ready: the sphere calms down.
    case done
}

/// The values a mood eases the sphere toward.
///
/// WHY targets and not one drawing per mood: a mood change in the middle of a turn
/// must not snap. The simulation moves every value toward its target a little on
/// each frame, so any mood can follow any other from wherever the sphere is.
public struct ParticleSphereTargets: Equatable, Sendable {
    /// Radians per second around the vertical axis.
    public var rotationSpeed: Double
    /// How much of the voice level reaches the surface, 0 to 1.
    public var voiceGain: Double
    /// How much the surface ripples, 0 to 1.
    public var ripple: Double
    /// How much the whole sphere breathes in and out, 0 to 1.
    public var pulse: Double

    public init(rotationSpeed: Double, voiceGain: Double, ripple: Double, pulse: Double) {
        self.rotationSpeed = rotationSpeed
        self.voiceGain = voiceGain
        self.ripple = ripple
        self.pulse = pulse
    }

    /// The targets Alex picked on the test benches (20 Nov 2026): a lively rotation at
    /// rest, a marked reaction to the voice, a breathing sphere while the text is
    /// cleaned up, a sphere that calms down at the end.
    /// Radians per second at rest and while listening. 0.42 is the speed the mesh
    /// sphere turned at on bench 5, where Alex validated it (0.7 with the dotted sphere).
    public static let restingRotationSpeed = 0.42

    public static func targets(for mood: ParticleSphereMood) -> ParticleSphereTargets {
        switch mood {
        case .resting:
            return ParticleSphereTargets(rotationSpeed: restingRotationSpeed, voiceGain: 0, ripple: 1, pulse: 0)
        case .listening:
            return ParticleSphereTargets(rotationSpeed: restingRotationSpeed, voiceGain: 1, ripple: 1, pulse: 0)
        case .working:
            return ParticleSphereTargets(rotationSpeed: 0.25, voiceGain: 0, ripple: 0.4, pulse: 1)
        case .done:
            return ParticleSphereTargets(rotationSpeed: 0.1, voiceGain: 0, ripple: 0.2, pulse: 0)
        }
    }
}

/// One dot of a frame, in the unit square: `x` and `y` run from 0 to 1 across the
/// view, `radius` is a fraction of the view's side.
public struct ParticleSphereDot: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    /// 0 to 1.
    public let opacity: Double
    /// 0 is the gradient's first colour, 1 its second.
    public let mix: Double
}

public enum ParticleSphereGeometry {
    /// "Fine and dense", the density picked on bench 2.
    public static let defaultPointCount = 1100

    /// `count` points spread evenly on the unit sphere (Fibonacci lattice).
    ///
    /// WHY this lattice: it needs no randomness, so the sphere is the same on every
    /// launch and in every test, and it has no poles where points bunch up, which is
    /// what a latitude and longitude grid gives.
    public static func fibonacciPoints(count: Int) -> [ParticleSpherePoint] {
        guard count > 0 else { return [] }
        let goldenAngle = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { index in
            let y = 1 - 2 * (Double(index) + 0.5) / Double(count)
            let ring = (1 - y * y).squareRoot()
            let angle = Double(index) * goldenAngle
            return ParticleSpherePoint(x: cos(angle) * ring, y: y, z: sin(angle) * ring)
        }
    }
}

/// The sphere's motion, advanced one frame at a time.
///
/// A value type with no clock of its own: the caller says how much time passed, which
/// is what makes it testable and keeps it identical in the app and in a preview.
public struct ParticleSphereSimulation: Equatable, Sendable {
    /// The eased values in force.
    public private(set) var current: ParticleSphereTargets
    /// Rotation around the vertical axis, in radians.
    public private(set) var angle: Double = 0
    /// Seconds of motion so far, which the ripples and the breathing are drawn from.
    public private(set) var time: Double = 0
    /// The whole sphere's scale, 1 at rest. Driven by a spring so a kick settles.
    public private(set) var scale: Double = 1
    /// The eased voice level, 0 to 1.
    public private(set) var level: Double = 0

    private var scaleVelocity: Double = 0
    private var springDamping: Double = Self.restDamping

    /// The sphere's radius as a fraction of the view's side. The rest is room for the
    /// ripples and the bounce, so no dot is ever clipped by the view's edge.
    public static let radiusFraction = 0.36

    private static let stiffness = 170.0
    private static let restDamping = 26.0
    /// Lighter than `restDamping`: this is what lets the wake overshoot once.
    private static let wakeDamping = 13.0
    /// The longest step one frame may take. A frame that arrives late (the app came
    /// back from the background) must not fling the spring.
    private static let maximumStep = 0.05
    /// The tilt of the rotation axis toward the viewer, in radians.
    private static let tilt = 0.38

    public init(mood: ParticleSphereMood = .resting) {
        current = ParticleSphereTargets.targets(for: mood)
    }

    /// The sphere wakes: it starts slightly smaller and springs back with one small
    /// overshoot. Bench 4's pick for entering the listening stage.
    public mutating func wake() {
        scale = 0.88
        scaleVelocity = 0
        springDamping = Self.wakeDamping
    }

    /// Move the simulation `elapsed` seconds forward.
    ///
    /// - Parameters:
    ///   - mood: what the sphere is saying now.
    ///   - voiceLevel: the microphone level, 0 to 1. Ignored outside `.listening`,
    ///     whose gain is the only one above zero.
    ///   - elapsed: seconds since the previous call.
    ///   - reduceMotion: with Reduce Motion the sphere neither turns nor ripples nor
    ///     bounces; `dots` makes its brightness carry the state instead.
    public mutating func advance(
        mood: ParticleSphereMood,
        voiceLevel: Double,
        elapsed: Double,
        reduceMotion: Bool
    ) {
        let step = min(max(elapsed, 0), Self.maximumStep)
        let targets = ParticleSphereTargets.targets(for: mood)

        // Exponential easing: the same fraction of the remaining distance per unit of
        // time, whatever the frame rate.
        let ease = 1 - exp(-step * 4.5)
        current.rotationSpeed += (targets.rotationSpeed - current.rotationSpeed) * ease
        current.voiceGain += (targets.voiceGain - current.voiceGain) * ease
        current.ripple += (targets.ripple - current.ripple) * ease
        current.pulse += (targets.pulse - current.pulse) * ease

        // The voice rises fast and falls slowly, so the surface does not flicker
        // between two syllables.
        let clamped = min(max(voiceLevel, 0), 1)
        let voiceEase = 1 - exp(-step * (clamped > level ? 18 : 6))
        level += (clamped - level) * voiceEase

        // The breathing reads the clock in both modes: under Reduce Motion it is the
        // brightness that breathes.
        time += step

        guard !reduceMotion else {
            scale = 1
            scaleVelocity = 0
            springDamping = Self.restDamping
            return
        }

        angle += current.rotationSpeed * step
        // Kept small so `sin` and `cos` keep their precision over a long session.
        if angle > 2 * Double.pi { angle -= 2 * Double.pi }

        let acceleration = -Self.stiffness * (scale - 1) - springDamping * scaleVelocity
        scaleVelocity += acceleration * step
        scale += scaleVelocity * step
        if abs(scale - 1) < 0.0005, abs(scaleVelocity) < 0.0005 {
            scale = 1
            scaleVelocity = 0
            springDamping = Self.restDamping
        }
    }

    /// The dots of the current frame, back to front in no particular order: they are
    /// translucent and small, so the order does not show.
    public func dots(
        points: [ParticleSpherePoint],
        mood: ParticleSphereMood,
        reduceMotion: Bool
    ) -> [ParticleSphereDot] {
        let drawnAngle = reduceMotion ? 0.6 : angle
        let drawnTime = reduceMotion ? 2.2 : time
        let cosAngle = cos(drawnAngle)
        let sinAngle = sin(drawnAngle)
        let cosTilt = cos(Self.tilt)
        let sinTilt = sin(Self.tilt)

        let voice = level * current.voiceGain
        let breathing = sin(time * 3.2)
        let drawnScale = reduceMotion ? 1 : scale * (1 + 0.055 * current.pulse * breathing)
        let amplitude = reduceMotion ? 0.4 : current.ripple * (0.3 + 2.1 * voice * 1.25)
        let brightness = Self.brightness(mood: mood, voice: level, breathing: breathing, reduceMotion: reduceMotion)

        return points.map { point in
            // Turn around the vertical axis, then tilt toward the viewer.
            let turnedX = point.x * cosAngle + point.z * sinAngle
            let turnedZ = -point.x * sinAngle + point.z * cosAngle
            let tiltedY = point.y * cosTilt - turnedZ * sinTilt
            let depthZ = point.y * sinTilt + turnedZ * cosTilt

            // Two slow waves across the surface, out of step with each other.
            let waveA = 0.065 * sin(3.2 * point.y + drawnTime * 1.5 + point.x * 2)
            let waveB = 0.045 * sin(4.1 * point.x + drawnTime * 1.05 + point.z * 3)
            let displacement = drawnScale * (1 + amplitude * (waveA + waveB))

            // 0 at the back of the sphere, 1 at the front.
            let depth = min(max((depthZ + 1) / 2, 0), 1)
            let mix = min(max((turnedX + tiltedY) * 0.45 + 0.5, 0), 1)

            return ParticleSphereDot(
                x: 0.5 + turnedX * Self.radiusFraction * displacement,
                y: 0.5 + tiltedY * Self.radiusFraction * displacement,
                radius: (0.5 + 3.0 * depth * depth) * 0.68 / 300,
                opacity: min(max((0.04 + 0.96 * depth * depth * depth) * brightness, 0), 1),
                mix: mix
            )
        }
    }

    /// With Reduce Motion the brightness carries what the motion no longer does: it
    /// follows the voice while listening and breathes slowly while working.
    private static func brightness(
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
            return 0.62 + 0.38 * (0.5 + 0.5 * breathing)
        case .resting, .done:
            return 1
        }
    }
}
