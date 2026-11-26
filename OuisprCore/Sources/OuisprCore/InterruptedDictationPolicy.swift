// OuisprCore/Sources/OuisprCore/InterruptedDictationPolicy.swift
// What a dictation does when an audio interruption cuts it (#851).
// Testable in isolation -- the coordinator supplies the status and the captured audio.

import Foundation

/// What stopped the engine under the dictation. Both arrive as the same
/// `ouisprAudioSessionInterrupted` post; the engine says which one it was.
public enum DictationInterruptionCause: String, Equatable, Sendable {
    /// An `AVAudioSession` interruption `.began`: a call, Siri, another app.
    case interruption
    /// `mediaServicesWereReset`: the audio server died and the engine was replaced.
    case mediaServicesReset
}

/// The dictation's answer to an interruption. The raw value is the log token.
public enum InterruptedDictationDecision: String, Equatable, Sendable {
    /// Nothing but silence was captured, in the first seconds: start the microphone again
    /// and keep listening. The user has not spoken yet, so there is nothing to end.
    case keepListening
    /// Stop as if the user had tapped stop, and transcribe what was captured.
    case transcribeCaptured
    /// Too little was captured to transcribe: the "no words" notice of a stop tapped a
    /// beat early, not a failure.
    case discardTooShort
    /// The audio was already collected; the transcription does not need the microphone.
    case letTranscriptionFinish
    /// Nothing to keep: the dictation fails, as every interruption did before #851.
    case fail
}

public enum InterruptedDictationPolicy {

    /// How long the opening silence of a recording is protected (audit of 26 Nov 2026:
    /// a dictation cut after one second with « Aucun mot détecté » before a word was said).
    public static let initialSilenceWindow: Double = 3

    /// The loudest sample, as a fraction of full scale, still counted as silence: about
    /// -40 dBFS, under a voice a metre away and over the floor of a quiet room.
    public static let silencePeak: Float = 0.01

    /// The decision for a dictation in `status` when an interruption arrives.
    ///
    /// WHY the recording is never resumed, only ended: `InterruptionResumePolicy`
    /// skips a recording on purpose (#353). Restarting the microphone after a call,
    /// behind the user's back, is the one thing worse than losing the audio.
    ///
    /// WHY a media services reset still fails: the reset replaces the engine under a
    /// tap that may be mid-write, and no device log has shown what the buffer holds
    /// afterwards. The reset is rare; the call is not. Only the measured case changes.
    ///
    /// - Parameters:
    ///   - capturedSeconds: the audio the engine holds, in seconds.
    ///   - minimum: the shortest clip a stop transcribes (the coordinator's
    ///     `minimumRecordingDuration`); a clip of exactly `minimum` is transcribed.
    ///   - capturedPeak: the loudest captured sample (0...1). The default, full scale,
    ///     says "something was heard" and keeps the decision it had before.
    ///
    /// WHY keeping on listening does not contradict #353: what #353 refuses is the
    /// microphone coming back after a call, behind the user's back. A call still holds
    /// the microphone, and the engine's own call guard refuses the restart; the caller
    /// then ends the recording exactly as before. What is restarted here is a recording
    /// the user started seconds ago and is still waiting to speak into.
    public static func decide(
        status: DictationStatus,
        cause: DictationInterruptionCause,
        capturedSeconds: Double,
        minimum: Double,
        capturedPeak: Float = 1
    ) -> InterruptedDictationDecision {
        guard cause == .interruption else { return .fail }
        switch status {
        case .recording:
            if capturedSeconds < initialSilenceWindow && capturedPeak < silencePeak {
                return .keepListening
            }
            return capturedSeconds >= minimum ? .transcribeCaptured : .discardTooShort
        case .transcribing, .processing:
            return .letTranscriptionFinish
        case .idle, .requested, .ready, .failed:
            return .fail
        }
    }
}
