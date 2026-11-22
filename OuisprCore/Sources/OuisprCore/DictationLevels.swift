// OuisprCore/Sources/OuisprCore/DictationLevels.swift
// The microphone levels and elapsed time of a dictation, published on their own.
import Combine
import Foundation

/// What the recording screen draws from the microphone: the recent levels and the
/// elapsed time.
///
/// WHY its own object and not two `@Published` properties of the coordinator: they
/// change about twelve times a second while recording, and every view observing the
/// coordinator (the root, Home under the recording screen, the recording screen itself)
/// re-rendered on each change, though only the sphere and the timer read them (audit,
/// 22 Nov 2026, finding 7). Observing this object instead confines those updates to
/// the two small views that need them.
@MainActor
public final class DictationLevels: ObservableObject {
    /// The rolling window of recent levels, 0 to 1, newest last.
    @Published public var energy: [Float] = []

    /// Seconds recorded so far.
    @Published public var seconds: Double = 0

    public init() {}

    /// The loudest of the last few levels, 0 to 1.
    ///
    /// WHY the last few and not the last one: one bucket is one short slice of sound;
    /// taking the peak of a few is what makes a syllable reach the sphere whole.
    public var recentPeak: Double {
        Double(energy.suffix(4).max() ?? 0)
    }

    /// The elapsed time as the stage label shows it, "m:ss".
    public var elapsedLabel: String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
