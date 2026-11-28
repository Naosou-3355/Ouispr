// OuisprCore/Tests/OuisprCoreTests/InkMicMorphTests.swift
// Pins the mic's morphing glyphs to the logo's bars and to each other.
import XCTest
@testable import OuisprCore

final class InkMicMorphTests: XCTestCase {

    func testEveryGlyphIsFourStrokesSoAnyTwoBlend() {
        for glyph in InkMicGlyph.allCases {
            XCTAssertEqual(glyph.strokes.count, 4, "\(glyph)")
        }
        XCTAssertEqual(InkMicGlyph.barsWithoutLeft.count, 4)
        XCTAssertEqual(InkMicGlyph.leftBarOnly.count, 4)
    }

    func testTheBarsAreTheLogosBars() {
        // InkMicBars: 5 wide, 9 apart, 9.1, 21.3 and 13.7 tall. A stroke's drawn height is
        // its length plus its width (the two round caps).
        let bars = InkMicGlyph.bars.strokes
        let heights = bars.map { abs($0.end.y - $0.start.y) + $0.width }
        XCTAssertEqual(Double(heights[0]), 9.1, accuracy: 1e-9)
        XCTAssertEqual(Double(heights[1]), 21.3, accuracy: 1e-9)
        XCTAssertEqual(Double(heights[2]), 13.7, accuracy: 1e-9)
        XCTAssertEqual(bars.map(\.start.x), [-9, 0, 9, -9])
        XCTAssertEqual(bars[3], bars[0], "stroke 4 is the left bar's twin")
    }

    func testTheTickIsThickerThanTheCross() {
        XCTAssertGreaterThan(InkMicGlyph.checkWidth, InkMicGlyph.crossWidth)
    }

    func testTheTickHidesTheLeftBarAndTheCrossKeepsOnlyIt() {
        let check = InkMicGlyph.check.strokes
        XCTAssertEqual(check[0].width, 0)
        XCTAssertEqual(check[3].width, 0)
        let cross = InkMicGlyph.cross.strokes
        XCTAssertEqual(cross[1].width, 0)
        XCTAssertEqual(cross[2].width, 0)
        XCTAssertEqual(InkMicGlyph.leftBarOnly[0], InkMicGlyph.bars.strokes[0])
        XCTAssertEqual(InkMicGlyph.barsWithoutLeft[1], InkMicGlyph.bars.strokes[1])
        XCTAssertEqual(InkMicGlyph.barsWithoutLeft[0].width, 0)
    }

    func testGlyphsStayInsideTheMicsBox() {
        // The box is 24 units; round caps reach half a width past each end.
        for glyph in InkMicGlyph.allCases {
            for stroke in glyph.strokes where stroke.width > 0 {
                for point in [stroke.start, stroke.end] {
                    XCTAssertLessThanOrEqual(abs(point.x) + stroke.width / 2, 12, "\(glyph)")
                    XCTAssertLessThanOrEqual(abs(point.y) + stroke.width / 2, 12, "\(glyph)")
                }
            }
        }
    }

    func testTheVectorRoundTripsAndBlends() {
        let bars = InkStrokeVector(InkMicGlyph.bars.strokes)
        let check = InkStrokeVector(InkMicGlyph.check.strokes)
        XCTAssertEqual(bars.strokes, InkMicGlyph.bars.strokes)
        var half = check - bars
        half.scale(by: 0.5)
        let middle = (bars + half).strokes
        XCTAssertEqual(Double(middle[1].width), Double(5 + InkMicGlyph.checkWidth) / 2, accuracy: 1e-9)
        XCTAssertEqual(InkStrokeVector.zero + bars, bars)
    }

    func testAnOvershootBelowZeroWidthDrawsNothing() {
        var vector = InkStrokeVector(InkMicGlyph.check.strokes)
        vector.values[4] = -0.4
        XCTAssertEqual(vector.strokes[0].width, 0)
    }

    func testTheLaughingEyesAreRoundHalfMoonsNotPoints() {
        // Lot 1.8 (Alex: « trop pointus »): each eye is two quarter arcs meeting at its
        // top, both arriving level there, so the top is a curve and not an angle.
        let smile = InkMicGlyph.smile.strokes
        for (rising, falling) in [(smile[0], smile[3]), (smile[1], smile[2])] {
            XCTAssertEqual(rising.end, falling.start, "the two halves meet at the top")
            XCTAssertEqual(rising.control.y, rising.end.y, "the rising half arrives level")
            XCTAssertEqual(falling.control.y, falling.start.y, "the falling half leaves level")
            XCTAssertEqual(rising.control.x, rising.start.x, "it leaves its foot upright")
            XCTAssertEqual(falling.control.x, falling.end.x, "it reaches its foot upright")
            let width = abs(falling.end.x - rising.start.x), height = abs(rising.start.y - rising.end.y)
            XCTAssertEqual(Double(height / (width / 2)), 0.95, accuracy: 1e-9, "the app's happy eye's proportion")
        }
        XCTAssertLessThan(smile[0].start.x, smile[1].start.x, "stroke 1 is the left eye, 2 the right")
    }

    func testABlendCarriesTheBendSoTheBarsSpringIntoTheArcs() {
        let bars = InkStrokeVector(InkMicGlyph.bars.strokes)
        let smile = InkStrokeVector(InkMicGlyph.smile.strokes)
        XCTAssertEqual(smile.strokes, InkMicGlyph.smile.strokes)
        var half = smile - bars
        half.scale(by: 0.5)
        let middle = (bars + half).strokes[0]
        let from = InkMicGlyph.bars.strokes[0].control, to = InkMicGlyph.smile.strokes[0].control
        XCTAssertEqual(Double(middle.control.x), Double(from.x + to.x) / 2, accuracy: 1e-9)
        XCTAssertEqual(Double(middle.control.y), Double(from.y + to.y) / 2, accuracy: 1e-9)
    }
}
