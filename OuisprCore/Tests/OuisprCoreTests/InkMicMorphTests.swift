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
}
