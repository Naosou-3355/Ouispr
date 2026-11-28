// OuisprCore/Tests/OuisprCoreTests/InkKeyboardWaveTests.swift
// Pins the keyboard's listening wave and its VU-meter envelope (lot 1.7).
import XCTest
@testable import OuisprCore

final class InkKeyboardWaveTests: XCTestCase {

    private func peak(_ level: Double, time: Double = 0.37) throws -> Double {
        try XCTUnwrap(InkGeometry.keyboardWave(level: level, time: time, samples: 97).map(abs).max())
    }

    func testTheWaveStartsAndEndsOnTheAxis() throws {
        for time in [0, 0.7, 12.3, 9_999.9] {
            let wave = InkGeometry.keyboardWave(level: 1, time: time, samples: 49)
            XCTAssertEqual(wave.count, 49)
            XCTAssertEqual(try XCTUnwrap(wave.first), 0, accuracy: 1e-9)
            XCTAssertEqual(try XCTUnwrap(wave.last), 0, accuracy: 1e-9)
        }
    }

    func testTheWaveFollowsTheVoiceWithinItsHeight() throws {
        XCTAssertLessThan(try peak(0), try peak(0.5))
        XCTAssertLessThan(try peak(0.5), try peak(1))
        XCTAssertEqual(try peak(3), try peak(1), accuracy: 1e-9)
        XCTAssertEqual(try peak(.nan), try peak(0), accuracy: 1e-9, "not a number reads as silence")
    }

    func testNoHeightEverLeavesTheAmplitude() {
        for level in [0, 0.3, 1] {
            let amplitude = InkGeometry.keyboardWaveFloor + (1 - InkGeometry.keyboardWaveFloor) * level
            for step in 0..<200 {
                let wave = InkGeometry.keyboardWave(level: level, time: Double(step) * 0.071, samples: 97)
                XCTAssertTrue(wave.allSatisfy { abs($0) <= amplitude + 1e-9 }, "level \(level) step \(step)")
            }
        }
    }

    func testSilenceBreathesAFewPercentAndKeepsMoving() throws {
        let silent = try peak(0)
        XCTAssertGreaterThan(silent, 0.005, "silence still shows a line that moves")
        XCTAssertLessThanOrEqual(silent, 0.04, "about 3 to 4 percent, never a voice")
        let now = InkGeometry.keyboardWave(level: 0, time: 1, samples: 97)
        let later = InkGeometry.keyboardWave(level: 0, time: 1.1, samples: 97)
        XCTAssertNotEqual(now, later, "the line moves even when nobody speaks")
    }

    func testTheWaveIsNotOneRepeatingSine() {
        // A single travelling sine keeps its shape: its peak height never changes. The
        // sum of three does, which is what reads as organic rather than mechanical.
        let peaks = (0..<40).map { step in
            InkGeometry.keyboardWave(level: 1, time: Double(step) * 0.05, samples: 97).map(abs).max() ?? 0
        }
        let spread = (peaks.max() ?? 0) - (peaks.min() ?? 0)
        XCTAssertGreaterThan(spread, 0.05)
    }

    func testAConstantTimeDrawsAStillLine() {
        XCTAssertEqual(
            InkGeometry.keyboardWave(level: 0, time: 0, samples: 97),
            InkGeometry.keyboardWave(level: 0, time: 0, samples: 97)
        )
    }

    func testAWaveOfOneSampleOrNoneIsFlat() {
        XCTAssertEqual(InkGeometry.keyboardWave(level: 1, time: 0, samples: 1), [0])
        XCTAssertEqual(InkGeometry.keyboardWave(level: 1, time: 0, samples: 0), [])
    }

    // MARK: - Envelope

    func testTheEnvelopeRisesFastAndFallsSlowly() {
        var rising = InkWaveEnvelope()
        rising.advance(toward: 1, elapsed: 0.05)
        XCTAssertEqual(rising.level, 1 - exp(-1), accuracy: 1e-9, "63 % of the way in one attack constant")

        var falling = InkWaveEnvelope(level: 1)
        falling.advance(toward: 0, elapsed: 0.05)
        XCTAssertGreaterThan(falling.level, 0.8, "a 50 ms pause barely lowers it")

        var settled = InkWaveEnvelope(level: 1)
        for _ in 0..<60 { settled.advance(toward: 0, elapsed: 1.0 / 60) }
        XCTAssertLessThan(settled.level, 0.05, "a second of silence brings it back down")
    }

    func testTheEnvelopeIsTheSameAtSixtyAndAtOneHundredTwentyHertz() {
        var sixty = InkWaveEnvelope()
        var hundredTwenty = InkWaveEnvelope()
        for _ in 0..<12 { sixty.advance(toward: 0.8, elapsed: 1.0 / 60) }
        for _ in 0..<24 { hundredTwenty.advance(toward: 0.8, elapsed: 1.0 / 120) }
        XCTAssertEqual(sixty.level, hundredTwenty.level, accuracy: 1e-9)
    }

    func testTheEnvelopeStaysInRangeAndIgnoresBadTime() {
        var envelope = InkWaveEnvelope(level: 0.4)
        envelope.advance(toward: 0.9, elapsed: -1)
        XCTAssertEqual(envelope.level, 0.4, accuracy: 1e-9)
        envelope.advance(toward: 0.9, elapsed: .nan)
        XCTAssertEqual(envelope.level, 0.4, accuracy: 1e-9)
        envelope.advance(toward: 5, elapsed: 30)
        XCTAssertLessThanOrEqual(envelope.level, 1)
        XCTAssertLessThan(envelope.level, 1, "a long suspension counts as 0.1 s, no jump")
        envelope.advance(toward: .nan, elapsed: 0.1)
        XCTAssertGreaterThanOrEqual(envelope.level, 0)
    }
}
