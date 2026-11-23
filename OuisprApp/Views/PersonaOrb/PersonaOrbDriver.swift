// OuisprApp/Views/PersonaOrb/PersonaOrbDriver.swift
// The character orb's animation: springs, gaze, blinks, from mood and voice to uniforms.
import Foundation
import OuisprCore

/// A damped spring, stepped by elapsed time.
///
/// WHY springs and not timed curves: a mood can change at any moment, and a spring
/// carries its velocity into the new target instead of restarting (WWDC23 "Animate with
/// springs"). `response` is the period in seconds, `damping` 1 for no overshoot.
struct OrbSpring {
    var value: Double
    var target: Double
    private var velocity: Double = 0
    private let stiffness: Double
    private let friction: Double

    init(_ value: Double, response: Double, damping: Double) {
        self.value = value
        self.target = value
        stiffness = pow(2 * .pi / response, 2)
        friction = 4 * .pi * damping / response
    }

    mutating func step(_ dt: Double) {
        // Fixed 4 ms substeps keep a stiff spring stable on a long frame.
        let count = max(1, Int((dt / 0.004).rounded(.up)))
        let h = dt / Double(count)
        for _ in 0..<count {
            let acceleration = -stiffness * (value - target) - friction * velocity
            velocity += acceleration * h
            value += velocity * h
        }
    }

    mutating func kick(_ dv: Double) { velocity += dv }

    mutating func settle() {
        value = target
        velocity = 0
    }
}

/// The uniforms of one frame, packed as the shader reads them.
struct PersonaOrbUniforms {
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var c: SIMD4<Float>
    var d: SIMD4<Float>
}

/// Drives the character orb (direction "Personnage", variant "Fidèle", chosen on the
/// bench of 23 Nov 2026). A line-for-line port of the bench's `PersoAnim`.
///
/// A reference type on purpose: Home and the recording screen show the same orb, and
/// share one driver so the one that appears carries on the gaze and the turn.
final class PersonaOrbDriver {
    static let shared = PersonaOrbDriver()

    private var gazeX = OrbSpring(0, response: 0.45, damping: 0.78)
    private var gazeY = OrbSpring(0, response: 0.45, damping: 0.78)
    private var lagX = OrbSpring(0, response: 0.9, damping: 0.9)
    private var lagY = OrbSpring(0, response: 0.9, damping: 0.9)
    private var squash = OrbSpring(0, response: 0.5, damping: 0.35)
    private var open = OrbSpring(1, response: 0.3, damping: 0.8)
    private var squint = OrbSpring(0, response: 0.35, damping: 0.62)
    private var bob = OrbSpring(0, response: 0.25, damping: 1)
    private var swirl = OrbSpring(0.12, response: 0.6, damping: 1)
    private var glow = OrbSpring(1, response: 0.5, damping: 1)
    private var speed = OrbSpring(0.3, response: 0.8, damping: 1)
    /// Underdamped voice level for the outer halo: a small overshoot on syllable peaks.
    private var level = OrbSpring(0, response: 0.30, damping: 0.45)

    // Same two-stage voice smoothing as the sphere it replaces: fast rise, slow fall.
    private var envelope = 0.0
    private var voice = 0.0

    private var phase = 0.0
    private var spin = 0.0
    private var nextLook = 0.8
    private var nextBlink = 1.8
    private var blinkTime = -1.0
    private var doubleBlink = false
    private var blink = 0.0
    private var previousMood: ParticleSphereMood?
    private var lastDate: Date?
    private var random = SplitMix(seed: 7)

    /// Advances to `date` and returns the frame's uniforms.
    ///
    /// - Parameters:
    ///   - advancing: false for a paused orb, drawn once without moving the clock.
    ///   - reduceMotion: loops stand still (no turning, no wandering gaze, no blinks);
    ///     only the brightness follows the voice, as in the sphere it replaces.
    func frame(
        at date: Date,
        mood: ParticleSphereMood,
        voiceLevel: Double,
        reduceMotion: Bool,
        advancing: Bool
    ) -> PersonaOrbUniforms {
        if advancing {
            // A long gap (paused, backgrounded) restarts from rest instead of jumping.
            let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 1.0 / 15.0) } ?? 0
            lastDate = date
            step(dt, mood: mood, voiceLevel: voiceLevel, reduceMotion: reduceMotion)
        } else {
            lastDate = nil
            if reduceMotion { settleForReduceMotion(mood: mood) }
        }
        return uniforms()
    }

    private func step(_ dt: Double, mood: ParticleSphereMood, voiceLevel: Double, reduceMotion: Bool) {
        let input = mood == .listening ? min(max(voiceLevel, 0), 1) : 0
        envelope += (input - envelope) * (1 - exp(-dt * (input > envelope ? 18 : 6)))
        voice += (envelope - voice) * (1 - exp(-dt * 12))
        let v = voice

        if mood != previousMood {
            if !reduceMotion, let previous = previousMood {
                switch mood {
                case .listening: squash.kick(-0.9); startBlink(double: false)
                case .done: squash.kick(-1.4); startBlink(double: true)
                case .working: nextLook = 0; squint.kick(1.5)
                case .resting: break
                }
                if previous == .working { squint.kick(-1.5) }
            }
            previousMood = mood
        }

        open.target = mood == .listening ? 1.12 + 0.1 * v : 1
        bob.target = mood == .listening ? 0.012 * v : 0
        squint.target = mood == .working ? 1 : 0
        switch mood {
        case .listening: swirl.target = 0.15 + 0.9 * v
        case .working: swirl.target = 0.7
        default: swirl.target = 0.12
        }
        glow.target = mood == .listening ? 1 + 0.4 * v : 1
        switch mood {
        case .listening: speed.target = 0.6 + 2.4 * v
        case .working: speed.target = 1.6
        default: speed.target = 0.3
        }
        level.target = mood == .listening ? v : 0

        if reduceMotion {
            settleForReduceMotion(mood: mood)
            return
        }

        updateGaze(dt, mood: mood)
        updateBlink(dt, mood: mood)

        gazeX.step(dt); gazeY.step(dt); squash.step(dt); open.step(dt); squint.step(dt)
        swirl.step(dt); glow.step(dt); speed.step(dt); bob.step(dt); level.step(dt)
        lagX.target = gazeX.value; lagY.target = gazeY.value
        lagX.step(dt); lagY.step(dt)
        phase += dt
        spin += dt * speed.value * 0.5
    }

    private func updateGaze(_ dt: Double, mood: ParticleSphereMood) {
        nextLook -= dt
        if nextLook <= 0 {
            let oldX = gazeX.target, oldY = gazeY.target
            switch mood {
            case .working:
                gazeX.target = 0.45; gazeY.target = 0.35; nextLook = 99
            case .listening:
                // Micro-saccades around one point: attentive rather than frozen.
                gazeX.target = (random.next() * 2 - 1) * 0.03
                gazeY.target = -0.05 + (random.next() * 2 - 1) * 0.02
                nextLook = 0.35 + random.next() * 0.35
            default:
                let angle = random.next() * 2 * .pi, reach = 0.15 + random.next() * 0.3
                gazeX.target = cos(angle) * reach; gazeY.target = sin(angle) * reach * 0.7
                nextLook = 1.4 + random.next() * 2.2
            }
            // People often blink as their eyes jump: about one big jump in two.
            if hypot(gazeX.target - oldX, gazeY.target - oldY) > 0.28, blinkTime < 0, random.next() < 0.45 {
                startBlink(double: false)
            }
        }
        if mood == .done { gazeX.target = 0; gazeY.target = 0 }
    }

    private func updateBlink(_ dt: Double, mood: ParticleSphereMood) {
        nextBlink -= dt
        if nextBlink <= 0, mood != .working, blinkTime < 0 {
            startBlink(double: random.next() < 0.15)
            nextBlink = 2.4 + random.next() * 3.2
        }
        blink = 0
        guard blinkTime >= 0 else { return }
        blinkTime += dt
        let total = 0.195
        // Asymmetric, like a real blink: 55 ms to close, 20 ms shut, 120 ms to open.
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        func one(_ t: Double) -> Double {
            if t < 0 { return 0 }
            if t < 0.055 { return smooth(t / 0.055) }
            if t < 0.075 { return 1 }
            if t < total { return 1 - smooth((t - 0.075) / 0.12) }
            return 0
        }
        blink = one(blinkTime)
        if doubleBlink, blinkTime > total + 0.09 { blink = one(blinkTime - total - 0.09) }
        if blinkTime > (doubleBlink ? 2 * total + 0.1 : total) { blinkTime = -1 }
    }

    private func startBlink(double: Bool) {
        blinkTime = 0
        doubleBlink = double
    }

    private func settleForReduceMotion(mood: ParticleSphereMood) {
        gazeX.target = mood == .working ? 0.45 : 0
        gazeY.target = mood == .working ? 0.35 : 0
        for keyPath in [\PersonaOrbDriver.gazeX, \.gazeY, \.squash, \.open, \.squint, \.bob, \.swirl, \.glow, \.speed] {
            self[keyPath: keyPath].settle()
        }
        // No turning and no halo swell: the brightness alone answers the voice.
        level.target = 0
        level.settle()
        lagX.target = gazeX.value; lagY.target = gazeY.value
        lagX.settle(); lagY.settle()
        blink = 0
        blinkTime = -1
    }

    private func uniforms() -> PersonaOrbUniforms {
        PersonaOrbUniforms(
            a: SIMD4(Float(phase), Float(spin), Float(gazeX.value), Float(gazeY.value)),
            b: SIMD4(Float(lagX.value), Float(lagY.value), Float(blink), Float(open.value)),
            c: SIMD4(Float(min(1.2, max(-0.2, squint.value))), Float(bob.value), Float(max(0, swirl.value)), Float(squash.value * 0.06)),
            d: SIMD4(Float(glow.value), Float(max(0, level.value)), 1, 1)
        )
    }
}

/// A small seeded generator, so the orb's wandering is the same on every run (and on
/// the bench, which used the same seed).
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
