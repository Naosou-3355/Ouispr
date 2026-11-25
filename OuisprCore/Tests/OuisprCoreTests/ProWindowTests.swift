// OuisprCore/Tests/OuisprCoreTests/ProWindowTests.swift
// The Ouispr Pro window's layout and trial timeline (Pro offer V1, 25 Nov 2026).
import XCTest
@testable import OuisprCore

final class ProWindowTests: XCTestCase {

    func testFromSettingsTheFourFeaturesInTheBenchOrder() {
        let layout = ProWindowLayout.layout(for: .settings)
        XCTAssertNil(layout.focus)
        XCTAssertEqual(layout.rows, [.smartMode, .vocabulary, .history, .voiceNotes])
    }

    func testATouchedFeatureLeadsAndIsNeverListedTwice() {
        for feature in ProFeature.allCases {
            let layout = ProWindowLayout.layout(for: .feature(feature))
            XCTAssertEqual(layout.focus, feature)
            XCTAssertFalse(layout.rows.contains(feature))
            XCTAssertEqual(layout.rows.count, 3)
        }
    }

    func testTheOrderCoversEveryFeatureOnce() {
        XCTAssertEqual(Set(ProWindowLayout.order), Set(ProFeature.allCases))
        XCTAssertEqual(ProWindowLayout.order.count, ProFeature.allCases.count)
    }

    func testEveryFeatureHasItsFocusCopy() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(feature.focusTitle.isEmpty)
            XCTAssertFalse(feature.focusLine.isEmpty)
        }
    }

    func testTheHistorySentenceStatesTheFreeWindow() {
        XCTAssertTrue(ProFeature.history.focusLine.contains("\(HistoryAvailability.freeSearchDays) days"))
    }

    func testTheTimelineMatchesTheTrialAndItsReminder() {
        let steps = ProTrialTimeline.steps()
        XCTAssertEqual(steps.map(\.day), [0, ProTrial.durationDays - ProTrial.reminderLeadDays, ProTrial.durationDays])
        XCTAssertEqual(steps.map(\.day), [0, 12, 14])
        XCTAssertEqual(steps[1].title, "Day 12")
    }
}
