// OuisprCore/Tests/OuisprCoreTests/DictationSampleStoreTests.swift
// The opt-in collection mode: off means nothing written, on means audio + texts round-trip.
import XCTest
@testable import OuisprCore

final class DictationSampleStoreTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("samples-\(UUID().uuidString)", isDirectory: true)
        suiteName = "DictationSampleStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore(enabled: Bool = true) -> DictationSampleStore {
        let store = DictationSampleStore(rootURL: root, defaults: defaults)
        store.isEnabled = enabled
        return store
    }

    private let policy = TranscriptionLanguagePolicy(
        mode: .explicit(.french),
        keyboardLanguage: .french,
        engine: .whisperKit,
        modelIdentifier: "openai_whisper-small"
    )

    private func record(_ store: DictationSampleStore, text: String = "bonjour à tous") -> UUID? {
        store.recordIfEnabled(
            samples: [Float](repeating: 0.25, count: 16_000),
            transcript: DictationTranscript(engine: "bonjour a tous", corrected: text),
            policy: policy,
            origin: .keyboard
        )
    }

    // MARK: - Off

    func testOffByDefault() {
        XCTAssertFalse(DictationSampleStore(rootURL: root, defaults: defaults).isEnabled)
    }

    func testOffWritesNothing() {
        let store = makeStore(enabled: false)
        XCTAssertNil(record(store))
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testEmptyAudioOrTextIsNotCollected() {
        let store = makeStore()
        XCTAssertNil(store.recordIfEnabled(
            samples: [], transcript: DictationTranscript(engine: "a", corrected: "a"),
            policy: policy, origin: .app))
        XCTAssertNil(record(store, text: "  "))
    }

    // MARK: - On

    func testRecordRoundTripsTextsAndAudio() throws {
        let store = makeStore()
        let id = try XCTUnwrap(record(store))
        store.setPolished("Bonjour à tous.", for: id)
        store.setCorrection("  Bonjour à toutes.  ", for: id)

        let sample = try XCTUnwrap(store.all().first)
        XCTAssertEqual(sample.id, id)
        XCTAssertEqual(sample.raw, "bonjour à tous")
        XCTAssertEqual(sample.engineRaw, "bonjour a tous")
        XCTAssertEqual(sample.polished, "Bonjour à tous.")
        XCTAssertEqual(sample.correction, "Bonjour à toutes.")
        XCTAssertEqual(sample.language, "fr")
        XCTAssertEqual(sample.origin, "keyboard")
        XCTAssertEqual(sample.durationSeconds, 1, accuracy: 0.001)

        let audio = try Data(contentsOf: try XCTUnwrap(store.audioURL(for: id)))
        XCTAssertEqual(audio.count, 44 + 16_000 * 2)
    }

    func testEmptyCorrectionClearsIt() throws {
        let store = makeStore()
        let id = try XCTUnwrap(record(store))
        store.setCorrection("x", for: id)
        store.setCorrection("   ", for: id)
        XCTAssertNil(store.all().first?.correction)
    }

    func testPolishedForNilIdIsIgnored() {
        let store = makeStore()
        store.setPolished("x", for: nil)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testNewestFirstAndDelete() throws {
        let store = makeStore()
        let first = try XCTUnwrap(record(store, text: "un"))
        Thread.sleep(forTimeInterval: 0.01)
        let second = try XCTUnwrap(record(store, text: "deux"))
        XCTAssertEqual(store.all().map(\.id), [second, first])

        store.delete(id: second)
        XCTAssertEqual(store.all().map(\.id), [first])
        store.deleteAll()
        XCTAssertTrue(store.all().isEmpty)
    }

    // MARK: - WAV

    func testWAVHeader() {
        let data = WAVEncoder.encode(samples: [0, 1, -1, 2], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + 8)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        // 2 is clamped to full scale, like 1.
        XCTAssertEqual(data[46..<48], data[50..<52])
    }
}
