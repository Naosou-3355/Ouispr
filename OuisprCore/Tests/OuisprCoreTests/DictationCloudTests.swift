// OuisprCore/Tests/OuisprCoreTests/DictationCloudTests.swift
// Pins the card cloud's rules: title, periods, rows and drift.
import XCTest
@testable import OuisprCore

final class DictationCloudTests: XCTestCase {

    func testTitleKeepsThreeWordsOfTheFirstSentence() {
        XCTAssertEqual(DictationCloud.title(for: "je serai en retard de 10 minutes. Commencez sans moi."), "Je serai")
        XCTAssertEqual(DictationCloud.title(for: "Peux-tu réserver les billets ?"), "Peux-tu réserver")
        XCTAssertEqual(DictationCloud.title(for: "Pour le point budget"), "Pour le point")
        XCTAssertEqual(DictationCloud.title(for: "Courses : lait, œufs, pain."), "Courses lait œufs")
        XCTAssertEqual(DictationCloud.title(for: "  \n Bonjour Claire !"), "Bonjour Claire")
        XCTAssertEqual(DictationCloud.title(for: ""), "")
    }

    func testCardWidthStaysWithinItsBounds() {
        XCTAssertEqual(DictationCloud.cardWidth(forTitle: "A"), 116)
        XCTAssertEqual(DictationCloud.cardWidth(forTitle: String(repeating: "a", count: 40)), 220)
    }

    func testPeriods() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9)))
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: now) ?? now
        }
        XCTAssertEqual(DictationCloud.Period.of(day(0), now: now, calendar: calendar), .today)
        XCTAssertEqual(DictationCloud.Period.of(day(1), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(DictationCloud.Period.of(day(7), now: now, calendar: calendar), .week)
        XCTAssertEqual(DictationCloud.Period.of(day(8), now: now, calendar: calendar), .older)
    }

    func testHomeRowsAreThreeThenTwo() {
        XCTAssertEqual(DictationCloud.homeRows([1, 2, 3, 4, 5, 6]), [[1, 2, 3], [4, 5]])
        XCTAssertEqual(DictationCloud.homeRows([1, 2]), [[1, 2]])
        XCTAssertEqual(DictationCloud.homeRows([Int]()), [])
    }

    func testCloudRowsDealTheNewestAcrossTheFirstRows() {
        XCTAssertEqual(DictationCloud.cloudRows([1, 2, 3, 4, 5], perRow: 2), [[1, 4], [2, 5], [3]])
        XCTAssertEqual(DictationCloud.cloudRows([Int](), perRow: 4), [])
    }

    func testDriftRampsToItsSpeedAndStaysWithinTwoPeriods() {
        var track = DriftTrack(unit: 300, direction: -1)
        for _ in 0..<600 { track.step(1.0 / 60, targetSpeed: DictationCloud.driftSpeed) }
        XCTAssertEqual(track.speed, 10, accuracy: 0.01)
        XCTAssertLessThanOrEqual(track.x, 0)
        XCTAssertGreaterThan(track.x, -600)
    }

    func testHoldingStopsTheDrift() {
        var track = DriftTrack(unit: 300, direction: 1)
        for _ in 0..<120 { track.step(1.0 / 60, targetSpeed: 10) }
        for _ in 0..<120 { track.step(1.0 / 60, targetSpeed: 0) }
        XCTAssertEqual(track.speed, 0, accuracy: 0.001)
    }

    func testAFlingDecaysAndIsCapped() {
        var track = DriftTrack(unit: 300, direction: 1)
        track.release(velocity: 5000)
        XCTAssertEqual(track.fling, 1600)
        for _ in 0..<300 { track.step(1.0 / 60, targetSpeed: 0) }
        XCTAssertEqual(track.fling, 0)
    }
}
