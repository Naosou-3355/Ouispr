// OuisprCore/Sources/OuisprCore/Design/InkKeyboardWave.swift
// The ink wave the keyboard's listening screen draws in its centre.
import Foundation

/// The keyboard's listening wave (lot 1.6, Alex's bench of 28 Nov 2026): one ample line in
/// ink across the centre, as tall as the voice is loud. It took the place of the 1.4 eyes:
/// the ✓ and ✕ moved to the top corners, which leaves the centre to the wave, and the
/// character's expression moved onto the mic (`InkMicGlyph.smile`).
public extension InkGeometry {

    /// The quietest the wave gets while listening, as a share of its full height: a
    /// silent room still shows a line that breathes, so the screen does not read as frozen.
    static let keyboardWaveFloor = 0.08

    /// The wave's height while the words are worked out: no voice to follow, a calm line.
    static let keyboardWaveWorkingLevel = 0.2

    /// Returns `samples` heights from -1 to 1, left to right, for a line `phase` radians
    /// along. One and a half periods across, tapered to zero at both ends so the line
    /// starts and ends on the axis like a stroke of ink, never cut off at a frame edge.
    ///
    /// WHY HERE: the keyboard extension has no test bundle (see `TranscribingStageHold`).
    static func keyboardWave(level: Double, phase: Double, samples: Int) -> [Double] {
        guard samples > 1 else { return Array(repeating: 0, count: max(samples, 0)) }
        let amplitude = keyboardWaveFloor + (1 - keyboardWaveFloor) * clamp01(level)
        return (0..<samples).map { index in
            let t = Double(index) / Double(samples - 1)
            let taper = pow(sin(.pi * t), 1.5)
            return amplitude * taper * sin(2 * .pi * 1.5 * t + phase)
        }
    }
}
