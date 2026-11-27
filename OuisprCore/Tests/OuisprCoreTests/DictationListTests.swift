// OuisprCore/Tests/OuisprCoreTests/DictationListTests.swift
// Pins the rules of Home's recent rows and the history's sections.
import XCTest
@testable import OuisprCore

final class DictationListTests: XCTestCase {

    func testOnlyTextWithALetterOrADigitHasWords() {
        XCTAssertTrue(DictationList.hasWords("Bonjour Claire"))
        XCTAssertTrue(DictationList.hasWords("10"))
        XCTAssertFalse(DictationList.hasWords(" … ?! "))
        XCTAssertFalse(DictationList.hasWords(""))
    }

    func testRepeatsThatFollowEachOtherAreOneRow() {
        let items = ["C'est pas mal.", "c'est pas mal", "Autre chose", "C'est pas mal"]
        XCTAssertEqual(DictationList.droppingRepeats(items) { $0 }, ["C'est pas mal.", "Autre chose", "C'est pas mal"])
    }

    func testShownLeavesOutWordlessRecordsBeforeRepeats() {
        // The wordless record between two repeats does not keep them apart.
        XCTAssertEqual(DictationList.shown(["Oui", "…", "oui.", "Non"]) { $0 }, ["Oui", "Non"])
    }

    func testPeriods() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9)))
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: now) ?? now
        }
        XCTAssertEqual(DictationList.Period.of(day(0), now: now, calendar: calendar), .today)
        XCTAssertEqual(DictationList.Period.of(day(1), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(DictationList.Period.of(day(7), now: now, calendar: calendar), .week)
        XCTAssertEqual(DictationList.Period.of(day(8), now: now, calendar: calendar), .older)
    }

    func testSectionsKeepThePeriodsOrderAndLeaveEmptyOnesOut() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9)))
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: -offset, to: now) ?? now
        }
        let items = [(1, day(0)), (2, day(0)), (3, day(10))]
        let sections = DictationList.sections(items, now: now, calendar: calendar) { $0.1 }
        XCTAssertEqual(sections.map(\.period), [.today, .older])
        XCTAssertEqual(sections.map { $0.items.map(\.0) }, [[1, 2], [3]])
    }
}
