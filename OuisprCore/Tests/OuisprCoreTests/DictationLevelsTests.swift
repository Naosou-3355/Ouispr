// OuisprCore/Tests/OuisprCoreTests/DictationLevelsTests.swift
import XCTest
@testable import OuisprCore

@MainActor
final class DictationLevelsTests: XCTestCase {
    func testRecentPeakIsTheLoudestOfTheLastFour() {
        let levels = DictationLevels()
        levels.energy = [0.9, 0.1, 0.3, 0.2, 0.4]
        XCTAssertEqual(levels.recentPeak, 0.4, accuracy: 0.0001)
    }

    func testNoLevelsIsSilence() {
        XCTAssertEqual(DictationLevels().recentPeak, 0)
    }

    func testElapsedLabelIsMinutesAndPaddedSeconds() {
        let levels = DictationLevels()
        levels.seconds = 65.8
        XCTAssertEqual(levels.elapsedLabel, "1:05")
    }
}
