import XCTest
@testable import OuisprCore

final class DriftCruiseTests: XCTestCase {

    func testRightwardCruiseStaysInRangeFromStartToEnd() {
        let cruise = DriftCruise(from: -10, at: 0, unit: 500, direction: 1, speedFactor: 1)
        XCTAssertGreaterThan(cruise.start, -1000)
        XCTAssertLessThanOrEqual(cruise.start, -500)
        XCTAssertLessThanOrEqual(cruise.end, 0)
        XCTAssertEqual(cruise.end - cruise.start, 500, accuracy: 0.001)
    }

    func testLeftwardCruiseStaysInRangeFromStartToEnd() {
        let cruise = DriftCruise(from: -700, at: 0, unit: 500, direction: -1, speedFactor: 0.8)
        XCTAssertLessThanOrEqual(cruise.start, 0)
        XCTAssertGreaterThan(cruise.start, -500)
        XCTAssertGreaterThan(cruise.end, -1000)
        XCTAssertEqual(cruise.velocity, -8, accuracy: 0.001)
    }

    func testPositionIsContinuousWithWhereItStarted() {
        // The cruise may shift its start by whole periods; the row on screen must not move.
        let cruise = DriftCruise(from: -10, at: 100, unit: 500, direction: 1, speedFactor: 1)
        let wrapped = { (x: Double) -> Double in (x.truncatingRemainder(dividingBy: 500) + 500).truncatingRemainder(dividingBy: 500) }
        XCTAssertEqual(wrapped(cruise.x(at: 100)), wrapped(-10), accuracy: 0.001)
        XCTAssertEqual(wrapped(cruise.x(at: 103)), wrapped(20), accuracy: 0.001)
    }

    func testPeriodAtCruiseSpeed() {
        let cruise = DriftCruise(from: 0, at: 0, unit: 500, direction: 1, speedFactor: 1)
        XCTAssertEqual(cruise.period, 500 / DictationCloud.driftSpeed, accuracy: 0.001)
    }

    func testCopiesCoverTheScreenAtAnyOffset() {
        for unit in [420.0, 800, 1500] {
            let copies = DriftCruise.copies(unit: unit, width: 402)
            // The leftmost offset is just above -2 * unit.
            XCTAssertGreaterThanOrEqual(-2 * unit + Double(copies) * unit, 402)
        }
    }

    func testShortRowsDoNotLoop() {
        XCTAssertFalse(DriftCruise.loops(unit: 450, widestCard: 160, width: 402))
        XCTAssertTrue(DriftCruise.loops(unit: 600, widestCard: 160, width: 402))
    }

    func testNarrowRowSwaysAroundTheCentre() {
        let pan = DriftPan(rowWidth: 200, width: 402, margin: 20)
        XCTAssertEqual((pan.from + pan.to) / 2, 101, accuracy: 0.001)
        XCTAssertEqual(pan.to - pan.from, 48, accuracy: 0.001)
    }

    func testWideRowPansFromOneEndToTheOther() {
        let pan = DriftPan(rowWidth: 500, width: 402, margin: 20)
        XCTAssertEqual(pan.to, 20)
        XCTAssertEqual(pan.from, 402 - 20 - 500)
        XCTAssertGreaterThanOrEqual(pan.duration, 6)
    }
}
