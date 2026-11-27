// OuisprCore/Tests/OuisprCoreTests/InkKeyboardEyesTests.swift
// Pins the keyboard's listening eyes to the app's resting face.
import XCTest
@testable import OuisprCore

final class InkKeyboardEyesTests: XCTestCase {

    func testStillEyesAreTheRestingFace() {
        XCTAssertEqual(
            InkGeometry.listeningEyes(stretch: 0, gazeX: 0, blink: 0),
            InkGeometry.held(.resting, pose: .still)
        )
    }

    func testTheVoiceStretchesTheEyesUpToTwiceTheirHeight() throws {
        func height(_ frame: InkFrame) throws -> Double {
            guard case let .stroke(points, _) = try XCTUnwrap(frame.shapes.first) else {
                XCTFail("an eye is a stroke"); return 0
            }
            return abs(points[1].y - points[0].y)
        }
        let rest = try height(InkGeometry.listeningEyes(stretch: 0, gazeX: 0, blink: 0))
        XCTAssertEqual(try height(InkGeometry.listeningEyes(stretch: 1, gazeX: 0, blink: 0)), 2 * rest, accuracy: 1e-9)
        XCTAssertEqual(try height(InkGeometry.listeningEyes(stretch: 5, gazeX: 0, blink: 0)), 2 * rest, accuracy: 1e-9)
        XCTAssertEqual(try height(InkGeometry.listeningEyes(stretch: 1, gazeX: 0, blink: 1)), 0, accuracy: 1e-9)
    }

    func testABlinkIsShortAndRare() {
        XCTAssertEqual(InkGeometry.keyboardBlink(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(InkGeometry.keyboardBlink(at: 0.075), 1, accuracy: 1e-9)
        XCTAssertEqual(InkGeometry.keyboardBlink(at: 0.2), 0)
        XCTAssertEqual(InkGeometry.keyboardBlink(at: 3.9), 0)
        XCTAssertEqual(InkGeometry.keyboardBlink(at: 4.075), 1, accuracy: 1e-9)
    }

    func testTheSweepStaysWithinItsReach() {
        for step in 0..<100 {
            XCTAssertLessThanOrEqual(abs(InkGeometry.keyboardSweep(at: Double(step) * 0.05)), InkGeometry.keyboardSweepReach + 1e-9)
        }
    }
}
