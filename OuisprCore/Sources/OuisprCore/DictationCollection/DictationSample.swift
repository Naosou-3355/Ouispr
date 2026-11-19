// OuisprCore/Sources/OuisprCore/DictationCollection/DictationSample.swift
// One collected dictation: what was said, what the pipeline made of it, and what it should have been.
import Foundation

/// One dictation kept by the opt-in collection mode, for an offline test bench built
/// from the user's own voice.
///
/// WHY four texts and not one: each pair measures a different stage. `engineRaw` vs
/// `raw` is the custom-vocabulary pass, `raw` vs `polished` is the cleanup, and
/// `polished` vs `correction` is what the whole pipeline still gets wrong. The audio
/// next to them lets a bench re-run the speech engine itself.
public struct DictationSample: Codable, Identifiable, Hashable, Sendable {

    public let id: UUID
    public let createdAt: Date
    /// Seconds of audio in `audio.wav`.
    public let durationSeconds: Double
    public let sampleRate: Int
    /// Same marker as `TranscriptionRecord.language`: "fr", "en", … or "auto".
    public let language: String
    /// `SpeechEngine.rawValue` ("WK" / "PK").
    public let engine: String
    /// `DictationOrigin.rawValue`: "keyboard" or "app".
    public let origin: String
    /// The speech engine's own output, when the vocabulary pass changed it. Nil means
    /// identical to `raw`.
    public let engineRaw: String?
    /// The transcript the cleanup received.
    public let raw: String
    /// What the cleanup produced, once it is known. Nil while a keyboard dictation is
    /// still being polished, or when the polish produced nothing.
    public internal(set) var polished: String?
    /// What the user says the text should have been. Nil until they write it.
    public internal(set) var correction: String?

    /// The file name of the audio, inside the sample's own folder.
    public static let audioFileName = "audio.wav"
    /// The file name of this record, inside the sample's own folder.
    public static let metadataFileName = "sample.json"

    public init(id: UUID = UUID(),
                createdAt: Date = Date(),
                durationSeconds: Double,
                sampleRate: Int,
                language: String,
                engine: String,
                origin: String,
                engineRaw: String?,
                raw: String,
                polished: String? = nil,
                correction: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.language = language
        self.engine = engine
        self.origin = origin
        self.engineRaw = engineRaw
        self.raw = raw
        self.polished = polished
        self.correction = correction
    }

    /// The text the user should see as the pipeline's final answer.
    public var finalText: String { polished ?? raw }
}
