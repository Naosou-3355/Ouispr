// OuisprCore/Sources/OuisprCore/Design/InkKeyboardEyes.swift
// The ink character's eyes as the keyboard's listening screen draws them.
import Foundation

/// The keyboard's listening face (lot 1.4, Alex's keyboard bench of 27 Nov 2026): only the
/// character's two eyes, at their own sizes, stretched by the voice, glancing aside while
/// the words are worked out, and the laughing eyes of `held(.done)` at the end.
///
/// WHY EYES AND NOT THE APP'S WAVE: the keyboard's listening area is about a third of the
/// app's screen. The wave needs its 128 pt to read as the logo; two eyes read at any size,
/// and they are the character the user already knows from Home.
public extension InkGeometry {

    /// How much taller the voice can make an eye: at full level, twice its resting height.
    static let keyboardMaximumStretch = 1.0

    /// How far the eyes glance aside while transcribing, in units of `gazeReach`.
    static let keyboardSweepReach = 0.45

    /// The resting eyes, stretched vertically by `stretch` (0 to 1, the voice's level),
    /// moved sideways by `gazeX` and closed by `blink` (0 open, 1 shut).
    ///
    /// `listeningEyes(stretch: 0, gazeX: 0, blink: 0)` is `held(.resting)`'s frame, so the
    /// keyboard's face at rest is the app's.
    static func listeningEyes(stretch: Double, gazeX: Double, blink: Double) -> InkFrame {
        let grow = 1 + keyboardMaximumStretch * clamp01(stretch)
        let half = eyeHalfHeight * grow * (1 - clamp01(blink))
        let shapes: [InkShape] = [-1.0, 1].map { side in
            let x = side * eyeX + gazeX * gazeReach
            return .stroke(points: [InkPoint(x, eyeY - half), InkPoint(x, eyeY + half)], width: eyeWidth)
        }
        return InkFrame(shapes: shapes, shade: 0)
    }

    /// The blink at `time` seconds: shut for 0.15 s every 4 s, a quick close and open.
    static func keyboardBlink(at time: Double) -> Double {
        let period = 4.0, duration = 0.15
        let phase = time.truncatingRemainder(dividingBy: period)
        guard phase >= 0, phase < duration else { return 0 }
        return sin(.pi * phase / duration)
    }

    /// The glance while transcribing: a slow sway from one side to the other, 2.4 s a cycle.
    static func keyboardSweep(at time: Double) -> Double {
        keyboardSweepReach * sin(2 * .pi * time / 2.4)
    }
}
