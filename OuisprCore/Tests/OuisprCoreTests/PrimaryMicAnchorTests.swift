// OuisprCore/Tests/OuisprCoreTests/PrimaryMicAnchorTests.swift
// Pins the arithmetic that places the recording screen's button and its flight from Home's mic (#788).
import XCTest
@testable import OuisprCore

final class PrimaryMicAnchorTests: XCTestCase {

    func testSpacingPutsTheSlotCentreAtThreeQuarters() {
        // An 800 pt safe area: the slot's centre at 600 pt.
        let spacing = PrimaryMicAnchor.bottomSpacing(containerHeight: 800, slotHeight: 100, centreFraction: 0.75)
        XCTAssertEqual(spacing, 150)
        XCTAssertEqual(800 - spacing - 50, 600)
    }

    func testSpacingNeverGoesNegative() {
        XCTAssertEqual(PrimaryMicAnchor.bottomSpacing(containerHeight: 120, slotHeight: 100, centreFraction: 0.75), 0)
    }

    func testFlightOffsetMovesTheButtonOntoTheAnchor() {
        XCTAssertEqual(PrimaryMicAnchor.flightOffset(anchorY: 734, slotCentreY: 600), 134)
        XCTAssertEqual(PrimaryMicAnchor.flightOffset(anchorY: nil, slotCentreY: 600), 0)
        XCTAssertEqual(PrimaryMicAnchor.flightOffset(anchorY: 734, slotCentreY: nil), 0)
    }

    @MainActor
    func testReportRoundsToHalfPointsAndIgnoresNoise() {
        let anchor = PrimaryMicAnchor()
        anchor.report(centerY: 734.2)
        XCTAssertEqual(anchor.centerY, 734)
        anchor.report(centerY: 734.7)
        XCTAssertEqual(anchor.centerY, 734.5)
    }
}
