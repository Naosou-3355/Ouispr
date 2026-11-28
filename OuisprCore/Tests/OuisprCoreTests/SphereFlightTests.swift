// OuisprCore/Tests/OuisprCoreTests/SphereFlightTests.swift
import CoreGraphics
import XCTest
@testable import OuisprCore

final class SphereFlightTests: XCTestCase {
    private let slot = CGRect(x: 101, y: 120, width: 200, height: 200)
    private let home = CGRect(x: 81, y: 210, width: 240, height: 240)

    func testAtHomeTheSphereSitsOnHomesSpotInSlotCoordinates() {
        let frame = SphereFlight.frame(home: home, slot: slot, atHome: true)
        XCTAssertEqual(frame, CGRect(x: -20, y: 90, width: 240, height: 240))
    }

    func testAwayFromHomeTheSphereFillsTheSlot() {
        let frame = SphereFlight.frame(home: home, slot: slot, atHome: false)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    func testWithNoHomeTheSphereStaysInItsSlot() {
        let frame = SphereFlight.frame(home: nil, slot: slot, atHome: true)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    func testAnEmptyHomeFrameIsIgnored() {
        let frame = SphereFlight.frame(home: .zero, slot: slot, atHome: true)
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    func testANonSquareSlotGivesACentredSquare() {
        let wide = CGRect(x: 0, y: 0, width: 300, height: 180)
        let frame = SphereFlight.frame(home: nil, slot: wide, atHome: false)
        XCTAssertEqual(frame, CGRect(x: 60, y: 0, width: 180, height: 180))
    }
}
