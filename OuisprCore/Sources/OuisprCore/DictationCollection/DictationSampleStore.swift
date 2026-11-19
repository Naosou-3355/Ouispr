// OuisprCore/Sources/OuisprCore/DictationCollection/DictationSampleStore.swift
// The opt-in collection mode: keeps each dictation's audio and texts on the device, for export to a Mac.
import Foundation

/// Stores the dictations collected while the user has turned collection on.
///
/// **Off by default, and a no-op when off.** Every write entry point checks
/// `isEnabled` first, so a user who never opens the screen pays one UserDefaults
/// read per dictation and nothing else.
///
/// **Never on the dictation's critical path.** The pipeline calls `record` the moment
/// the transcript exists; the call returns an id at once and the WAV is written on a
/// private serial queue. Writes for one sample (record, then polished, then a
/// correction) run in the order they were asked for because the queue is serial.
///
/// Layout, inside the App Group container:
///
///     DictationSamples/
///       <uuid>/audio.wav     16 kHz mono 16-bit PCM
///       <uuid>/sample.json   a `DictationSample`
///       manifest.json        written at export: every sample, oldest first
///
/// WHY one folder per sample rather than one JSON array like the history: the audio
/// has to live in files anyway, and a folder per sample means a crash mid-write can
/// cost at most that sample, never the collection.
public final class DictationSampleStore: @unchecked Sendable {

    public static let shared = DictationSampleStore()

    /// The App Group key behind the Settings toggle.
    public static let enabledKey = "ouispr.dictationCollectionEnabled"
    public static let folderName = "DictationSamples"
    public static let manifestFileName = "manifest.json"

    private let rootURL: URL?
    private let defaults: UserDefaults
    // Serial: keeps the writes for one sample in the order they were asked for.
    private let queue = DispatchQueue(label: "ouispr.dictationSamples", qos: .utility)
    private let fileManager = FileManager.default

    /// - Parameters:
    ///   - rootURL: the collection folder. Defaults to the App Group container; the
    ///     tests pass a temporary folder.
    ///   - defaults: where the toggle lives.
    init(rootURL: URL? = AppGroup.containerURL?.appendingPathComponent(DictationSampleStore.folderName),
         defaults: UserDefaults = AppGroup.defaults) {
        self.rootURL = rootURL
        self.defaults = defaults
    }

    // MARK: - Toggle

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    // MARK: - Writing

    /// Keep one dictation, when collection is on. Returns the sample's id at once (the
    /// files are written in the background), or nil when collection is off, there is
    /// no audio or no text, or the container is unreachable.
    @discardableResult
    public func recordIfEnabled(samples: [Float],
                                sampleRate: Int = 16_000,
                                transcript: DictationTranscript,
                                policy: TranscriptionLanguagePolicy,
                                origin: DictationOrigin) -> UUID? {
        guard isEnabled, rootURL != nil, !samples.isEmpty else { return nil }
        guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sample = DictationSample(
            durationSeconds: Double(samples.count) / Double(sampleRate),
            sampleRate: sampleRate,
            language: TranscriptionRecord.languageCode(for: policy),
            engine: policy.engine.rawValue,
            origin: origin.rawValue,
            engineRaw: transcript.engineRaw,
            raw: transcript.text
        )
        queue.async { [self] in
            guard let folder = folderURL(for: sample.id) else { return }
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let wav = WAVEncoder.encode(samples: samples, sampleRate: sampleRate)
                try wav.write(to: folder.appendingPathComponent(DictationSample.audioFileName), options: .atomic)
                try write(sample)
            } catch {
                // A sample that failed to write is simply not collected; the dictation
                // itself is unaffected.
                try? fileManager.removeItem(at: folder)
            }
        }
        return sample.id
    }

    /// Record what the cleanup produced for a sample. Ignored for a nil id (collection
    /// was off for that dictation) or a sample that is gone.
    public func setPolished(_ text: String, for id: UUID?) {
        guard let id else { return }
        queue.async { [self] in
            guard var sample = read(id: id) else { return }
            sample.polished = text
            try? write(sample)
        }
    }

    /// Record what the text should have been. An empty or whitespace-only text clears it.
    public func setCorrection(_ text: String?, for id: UUID) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        queue.async { [self] in
            guard var sample = read(id: id) else { return }
            sample.correction = (trimmed?.isEmpty ?? true) ? nil : trimmed
            try? write(sample)
        }
    }

    public func delete(id: UUID) {
        queue.async { [self] in
            guard let folder = folderURL(for: id) else { return }
            try? fileManager.removeItem(at: folder)
        }
    }

    public func deleteAll() {
        queue.async { [self] in
            guard let rootURL else { return }
            try? fileManager.removeItem(at: rootURL)
        }
    }

    // MARK: - Reading

    /// Every sample on disk, newest first. Waits for pending writes.
    public func all() -> [DictationSample] {
        queue.sync { readAll() }.sorted { $0.createdAt > $1.createdAt }
    }

    /// The audio file of a sample, for playback.
    public func audioURL(for id: UUID) -> URL? {
        folderURL(for: id)?.appendingPathComponent(DictationSample.audioFileName)
    }

    // MARK: - Export

    /// Write `manifest.json` (every sample, oldest first) and zip the whole collection
    /// into a temporary file the share sheet can send to a Mac.
    ///
    /// WHY a zip: AirDrop and Files handle one file reliably, a folder of hundreds less
    /// so. `NSFileCoordinator`'s `.forUploading` is the system's own folder zipper.
    public func makeExportArchive(now: Date = Date()) throws -> URL {
        try queue.sync {
            guard let rootURL else { throw CocoaError(.fileNoSuchFile) }
            let samples = readAll().sorted { $0.createdAt < $1.createdAt }
            guard !samples.isEmpty else { throw CocoaError(.fileNoSuchFile) }
            try Self.encoder.encode(samples)
                .write(to: rootURL.appendingPathComponent(Self.manifestFileName), options: .atomic)

            let stamp = Self.fileStamp.string(from: now)
            let destination = fileManager.temporaryDirectory
                .appendingPathComponent("Ouispr-dictees-\(stamp).zip")
            try? fileManager.removeItem(at: destination)

            var coordinationError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: rootURL, options: .forUploading, error: &coordinationError) { zipURL in
                do { try fileManager.copyItem(at: zipURL, to: destination) } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError { throw error }
            return destination
        }
    }

    // MARK: - Files (queue only)

    private func folderURL(for id: UUID) -> URL? {
        rootURL?.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func read(id: UUID) -> DictationSample? {
        guard let url = folderURL(for: id)?.appendingPathComponent(DictationSample.metadataFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(DictationSample.self, from: data)
    }

    private func write(_ sample: DictationSample) throws {
        guard let url = folderURL(for: sample.id)?.appendingPathComponent(DictationSample.metadataFileName) else { return }
        try Self.encoder.encode(sample).write(to: url, options: .atomic)
    }

    private func readAll() -> [DictationSample] {
        guard let rootURL,
              let folders = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        else { return [] }
        return folders.compactMap { UUID(uuidString: $0.lastPathComponent) }.compactMap(read(id:))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Milliseconds kept: plain `.iso8601` drops them, and two dictations in the
        // same second would then sort in no particular order.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DictationSampleStore.isoFormatter.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = DictationSampleStore.isoFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(text)"))
        }
        return decoder
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}
