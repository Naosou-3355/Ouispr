// OuisprCore/Tests/OuisprCoreTests/TranscriptionSearchWindowTests.swift
// The free search window: 7 days, older matches counted for Pro (Pro offer, 25 Nov 2026).
import XCTest
@testable import OuisprCore

final class TranscriptionSearchWindowTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func record(_ text: String, daysAgo: Double) -> TranscriptionRecord {
        TranscriptionRecord(text: text, language: "fr", durationSeconds: 3,
                            createdAt: now.addingTimeInterval(-daysAgo * day), sttProvider: "PK")
    }

    private lazy var records = [
        record("Devis plombier confirmé", daysAgo: 1),
        record("Rappeler le plombier", daysAgo: 6.9),
        record("Devis plombier du 18", daysAgo: 12),
        record("Courses", daysAgo: 30)
    ]

    func testFreeSearchKeepsTheLastSevenDaysAndCountsTheRest() {
        let result = TranscriptionSearch.search(records, query: "plombier", now: now, windowDays: 7, unlimited: false)
        XCTAssertEqual(result.found.map(\.text), ["Devis plombier confirmé", "Rappeler le plombier"])
        XCTAssertEqual(result.olderMatches, 1)
    }

    func testProSearchFindsEverything() {
        let result = TranscriptionSearch.search(records, query: "plombier", now: now, windowDays: 7, unlimited: true)
        XCTAssertEqual(result.found.count, 3)
        XCTAssertEqual(result.olderMatches, 0)
    }

    func testAnEmptyQueryShowsTheWholeHistoryForFree() {
        // The history itself is free: only searching it far back is Pro.
        let result = TranscriptionSearch.search(records, query: "  ", now: now, windowDays: 7, unlimited: false)
        XCTAssertEqual(result.found.count, 4)
        XCTAssertEqual(result.olderMatches, 0)
    }

    func testNoOlderMatchWhenNothingOldMatches() {
        let result = TranscriptionSearch.search(records, query: "confirmé", now: now, windowDays: 7, unlimited: false)
        XCTAssertEqual(result.found.count, 1)
        XCTAssertEqual(result.olderMatches, 0)
    }
}
