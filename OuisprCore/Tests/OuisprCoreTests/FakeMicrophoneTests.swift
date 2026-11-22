// OuisprCore/Tests/OuisprCoreTests/FakeMicrophoneTests.swift
#if DEBUG
import AVFoundation
import XCTest
@testable import OuisprCore

final class FakeMicrophoneTests: XCTestCase {
    func testPlaysTheRecordingInOrderThenSilence() {
        let microphone = FakeMicrophone(samples: [1, 2, 3, 4, 5])
        XCTAssertEqual(microphone.next(count: 2), [1, 2])
        XCTAssertEqual(microphone.next(count: 2), [3, 4])
        XCTAssertEqual(microphone.next(count: 3), [5, 0, 0])
        XCTAssertEqual(microphone.next(count: 2), [0, 0])
    }

    func testRewindStartsAgainFromTheFirstSample() {
        let microphone = FakeMicrophone(samples: [1, 2, 3])
        _ = microphone.next(count: 5)
        microphone.rewind()
        XCTAssertEqual(microphone.next(count: 2), [1, 2])
    }

    func testNoSettingMeansNoFakeMicrophone() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FakeMicrophoneTests.none"))
        defaults.removePersistentDomain(forName: "FakeMicrophoneTests.none")
        XCTAssertNil(FakeMicrophone.configured(environment: [:], defaults: defaults))
    }

    func testAMissingFileMeansNoFakeMicrophone() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FakeMicrophoneTests.missing"))
        defaults.removePersistentDomain(forName: "FakeMicrophoneTests.missing")
        let environment = [FakeMicrophone.environmentKey: "/nonexistent/voice.wav"]
        XCTAssertNil(FakeMicrophone.configured(environment: environment, defaults: defaults))
    }

    /// A 1 s, 44.1 kHz stereo file comes out as about 1 s of 16 kHz mono.
    func testAFileIsConvertedTo16kHzMono() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-mic-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<44100 {
            let value = Float(sin(Double(frame) * 2 * .pi * 440 / 44100)) * 0.5
            channels[0][frame] = value
            channels[1][frame] = value
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }

        let microphone = try XCTUnwrap(FakeMicrophone.configured(
            environment: [FakeMicrophone.environmentKey: url.path],
            defaults: .standard
        ))
        XCTAssertEqual(Double(microphone.samples.count), 16000, accuracy: 400)
        XCTAssertGreaterThan(microphone.samples.map(abs).max() ?? 0, 0.3)
    }
}
#endif
