// OuisprCore/Tests/OuisprCoreTests/InkKeyboardWaveTests.swift
// Pins the keyboard's listening wave.
import XCTest
@testable import OuisprCore

final class InkKeyboardWaveTests: XCTestCase {

    func testTheWaveStartsAndEndsOnTheAxis() throws {
        let wave = InkGeometry.keyboardWave(level: 1, phase: 0.7, samples: 49)
        XCTAssertEqual(wave.count, 49)
        XCTAssertEqual(try XCTUnwrap(wave.first), 0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(wave.last), 0, accuracy: 1e-9)
    }

    func testTheWaveFollowsTheVoiceWithinItsHeight() throws {
        func peak(_ level: Double) throws -> Double {
            try XCTUnwrap(InkGeometry.keyboardWave(level: level, phase: 0, samples: 97).map(abs).max())
        }
        XCTAssertGreaterThan(try peak(0), 0, "silence still breathes")
        XCTAssertLessThan(try peak(0), try peak(0.5))
        XCTAssertLessThan(try peak(0.5), try peak(1))
        XCTAssertLessThanOrEqual(try peak(3), 1)
        XCTAssertEqual(try peak(3), try peak(1), accuracy: 1e-9)
    }

    func testAWaveOfOneSampleOrNoneIsFlat() {
        XCTAssertEqual(InkGeometry.keyboardWave(level: 1, phase: 0, samples: 1), [0])
        XCTAssertEqual(InkGeometry.keyboardWave(level: 1, phase: 0, samples: 0), [])
    }
}
