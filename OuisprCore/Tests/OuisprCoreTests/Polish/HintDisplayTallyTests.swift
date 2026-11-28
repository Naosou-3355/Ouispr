// OuisprCore/Tests/OuisprCoreTests/Polish/HintDisplayTallyTests.swift
// The hint is counted once per opening that drew it (lot 1.7).
import XCTest
@testable import OuisprCore

final class HintDisplayTallyTests: XCTestCase {

    func testNineViewsDrawingItCountOnce() {
        var tally = HintDisplayTally(displayCount: 0)
        tally.keyboardOpened(displayCount: 0)
        let counted = (0..<9).filter { _ in tally.hintDrawn() }.count
        XCTAssertEqual(counted, 1)
    }

    func testEachOpeningCountsAgain() {
        var tally = HintDisplayTally(displayCount: 0)
        tally.keyboardOpened(displayCount: 0)
        XCTAssertTrue(tally.hintDrawn())
        tally.keyboardOpened(displayCount: 1)
        XCTAssertEqual(tally.displaysBeforeThisOpening, 1)
        XCTAssertTrue(tally.hintDrawn())
    }

    /// An opening where the slot showed something else draws nothing and counts nothing.
    func testAnOpeningThatNeverDrewItCountsNothing() {
        var tally = HintDisplayTally(displayCount: 2)
        tally.keyboardOpened(displayCount: 2)
        XCTAssertFalse(tally.countedThisOpening)
        tally.keyboardOpened(displayCount: 2)
        XCTAssertEqual(tally.displaysBeforeThisOpening, 2)
    }

    func testAnAppearanceAfterNobodyOrAnAppSwitchIsAnOpening() {
        let owned = KeyboardOwnership.owned(controllerID: "a")
        XCTAssertTrue(owned.opensKeyboard(appearingAfter: .none))
        XCTAssertTrue(owned.opensKeyboard(appearingAfter: .awaitingReclaim(previousControllerID: "b")),
                      "the successor iOS builds after an app switch")
        XCTAssertFalse(owned.opensKeyboard(appearingAfter: .owned(controllerID: "b")),
                       "a second controller while one is on screen is the same opening")
        XCTAssertFalse(KeyboardOwnership.none.opensKeyboard(appearingAfter: .none))
    }
}
