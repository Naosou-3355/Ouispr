// OuisprCore/Sources/OuisprCore/Design/InkKeyboardWave.swift
// The ink wave the keyboard's listening screen draws in its centre.
import Foundation

/// The keyboard's listening wave: one ample line in ink across the centre, as tall as the
/// voice is loud.
///
/// Lot 1.7 (Alex's iPhone video of the 1.6, 28 Nov 2026): one sine read as dead at silence
/// (flat and frozen) and then as mechanical while speaking. The line is now the sum of three
/// sines of different lengths travelling at different speeds, so its shape never repeats in
/// a way the eye can follow (the organic look of Siri's and Voice Memos' waves), still drawn
/// as a single 2 pt stroke tapered to nothing at both ends. At silence it keeps breathing,
/// a few percent of its height and always moving, so the screen says "I am listening".
public extension InkGeometry {

    /// The quietest the wave gets while listening, as a share of its full height: a
    /// silent room still shows a line that moves, so the screen does not read as frozen.
    static let keyboardWaveFloor = 0.035

    /// The wave's height while the words are worked out: no voice to follow, a calm line.
    static let keyboardWaveWorkingLevel = 0.2

    /// Returns `samples` heights from -1 to 1, left to right, at `time` seconds.
    ///
    /// `level` (0 to 1, clamped) sets the height: `keyboardWaveFloor` at silence, the whole
    /// frame at full voice. The sum is divided by the components' total weight, so no
    /// height ever leaves -amplitude...amplitude. Tapered to zero at both ends so the line
    /// starts and ends on the axis like a stroke of ink, never cut off at a frame edge.
    /// A constant `time` draws a still line (Reduce Motion).
    ///
    /// WHY HERE: the keyboard extension has no test bundle (see `TranscribingStageHold`).
    static func keyboardWave(level: Double, time: Double, samples: Int) -> [Double] {
        guard samples > 1 else { return Array(repeating: 0, count: max(samples, 0)) }
        let amplitude: Double = keyboardWaveFloor + (1 - keyboardWaveFloor) * clamp01(level.isFinite ? level : 0)
        let components = InkWaveComponent.all
        let totalWeight: Double = components.reduce(0) { $0 + $1.weight }
        let safeTime: Double = time.isFinite ? time.truncatingRemainder(dividingBy: 10_000) : 0
        var heights: [Double] = []
        heights.reserveCapacity(samples)
        for index in 0..<samples {
            let t = Double(index) / Double(samples - 1)
            let taper: Double = pow(sin(Double.pi * t), 1.5)
            var sum: Double = 0
            for component in components {
                sum += component.weight * component.value(at: t, time: safeTime)
            }
            heights.append(amplitude * taper * sum / totalWeight)
        }
        return heights
    }
}

/// One of the sines the keyboard wave is the sum of.
struct InkWaveComponent {
    /// Periods across the line.
    let periods: Double
    /// Periods per second the sine travels; the sign is its direction.
    let speed: Double
    /// Its share of the sum.
    let weight: Double
    /// Where it starts, so the three never line up at time zero.
    let offset: Double

    func value(at position: Double, time: Double) -> Double {
        let turns: Double = periods * position + speed * time
        return sin(2 * Double.pi * turns + offset)
    }

    /// Three lengths whose ratios are not simple fractions (1.5, 2.6, 4.1), so their sum
    /// does not settle into a visible repeating pattern; the long one leads.
    static let all: [InkWaveComponent] = [
        InkWaveComponent(periods: 1.5, speed: -0.8, weight: 1, offset: 0),
        InkWaveComponent(periods: 2.6, speed: 1.15, weight: 0.55, offset: 1.9),
        InkWaveComponent(periods: 4.1, speed: -1.9, weight: 0.3, offset: 4.2)
    ]
}

/// The wave's level over time, the way a VU meter moves: it jumps up with the voice and
/// falls back slowly, so a syllable reads as a beat and a pause as a breath, never as a
/// flicker.
///
/// A first-order follower with two time constants, measured on the time that actually
/// passed so it behaves the same at 60 and at 120 Hz.
public struct InkWaveEnvelope: Equatable, Sendable {
    /// Time constant while the level rises (seconds).
    public static let attack: Double = 0.05
    /// Time constant while the level falls (seconds).
    public static let release: Double = 0.275

    /// The current level, 0 to 1.
    public private(set) var level: Double

    public init(level: Double = 0) {
        self.level = clamp01(level.isFinite ? level : 0)
    }

    /// Moves toward `target` (clamped to 0...1) for `elapsed` seconds and returns the new
    /// level. Elapsed is capped at 0.1 s, and a negative or not-a-number one counts as no
    /// time, so a keyboard resumed after a suspension does not jump.
    @discardableResult
    public mutating func advance(toward target: Double, elapsed: Double) -> Double {
        let goal: Double = clamp01(target.isFinite ? target : 0)
        let step: Double = elapsed.isFinite ? min(max(elapsed, 0), 0.1) : 0
        let constant: Double = goal > level ? Self.attack : Self.release
        let blend: Double = 1 - exp(-step / constant)
        level += (goal - level) * blend
        return level
    }
}
