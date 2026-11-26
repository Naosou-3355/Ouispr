// OuisprApp/DictationCoordinator+RecordingReadiness.swift
// The listening state is shown only once the microphone delivers audio, and every stop
// says why it happened (audit of 26 Nov 2026: a dictation cut after one second with
// « Aucun mot détecté »).
//
// WHY a file of its own: DictationCoordinator.swift sits at the file-length budget of #146,
// the reason `DictationCoordinator+SessionActivation.swift` exists. The engine is passed in
// rather than exposed.
import Foundation
import OuisprCore

extension DictationCoordinator {

    /// How long a start waits for the first buffer before it says the microphone is live
    /// anyway. A warm engine delivers its first buffer in about 20 ms; a route that is
    /// still settling (a headset just connected) can take a few hundred.
    static let firstAudioTimeout: Duration = .milliseconds(1500)

    /// Wait until the engine has delivered its first samples, so the listening state is
    /// never shown over a microphone that is not capturing yet.
    ///
    /// WHY wait rather than fail: a start that is merely slow is not broken. When the
    /// timeout passes with nothing, the caller goes on to `verifyAudioFlow`, whose zombie
    /// recovery restarts the engine; failing here would only duplicate it, sooner.
    ///
    /// - Returns: whether audio arrived before the timeout. Throws only on cancellation.
    func awaitFirstAudio(from engine: UnifiedAudioEngine) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.firstAudioTimeout
        while engine.currentSampleCount == 0 {
            guard clock.now < deadline else {
                PersistentLog.log(.dictationDeferred(reason: "no audio 1.5 s after start: listening shown anyway"))
                return false
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// One line per stop: what ended the recording and what it held. The peak, never the
    /// audio or the words, is what tells "stopped before speaking" from "spoke, heard
    /// nothing".
    func logStop(cause: DictationStopCause, samples: [Float]) {
        let durationMs = samples.count * 1000 / 16000
        let peak = Double(UnifiedAudioEngine.peak(of: samples))
        PersistentLog.log(.dictationStopped(cause: cause.rawValue, durationMs: durationMs, peak: peak))
        OuisprLogger.app.notice(
            "Dictation stopped: cause=\(cause.rawValue, privacy: .public) duration=\(durationMs, privacy: .public)ms peak=\(peak, privacy: .public)"
        )
    }
}
