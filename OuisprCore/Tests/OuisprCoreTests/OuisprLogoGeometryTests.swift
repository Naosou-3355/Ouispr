// OuisprCore/Tests/OuisprCoreTests/OuisprLogoGeometryTests.swift
// The in-app logo is drawn from these ratios, so they are pinned against the app
// icon's own numbers (assets/brand/appicon-dark.svg) (#636).
import XCTest
@testable import OuisprCore

final class OuisprLogoGeometryTests: XCTestCase {

    private let accuracy: CGFloat = 0.0001

    /// At the SVG's own scale the functions must give back the SVG's numbers.
    /// If one of these fails, the in-app logo no longer matches the app icon.
    func testReproducesTheAppIconAtItsOwnScale() {
        let height: CGFloat = 42
        XCTAssertEqual(OuisprLogoGeometry.barWidth(forHeight: height), 9, accuracy: accuracy)
        XCTAssertEqual(OuisprLogoGeometry.gap(forHeight: height), 7.5, accuracy: accuracy)
        XCTAssertEqual(OuisprLogoGeometry.tileSide(forHeight: height), 80, accuracy: accuracy)
        XCTAssertEqual(OuisprLogoGeometry.tileCornerRadius(forSide: 80), 18, accuracy: accuracy)
        XCTAssertEqual(OuisprLogoGeometry.tileStrokeWidth(forSide: 80), 1, accuracy: accuracy)

        let heights = OuisprLogoGeometry.barHeightRatios.map { $0 * height }
        XCTAssertEqual(heights.count, 3)
        XCTAssertEqual(heights[0], 18, accuracy: accuracy)
        XCTAssertEqual(heights[1], 42, accuracy: accuracy)
        XCTAssertEqual(heights[2], 27, accuracy: accuracy)
    }

    /// The bug #636 fixed: every size scales with the height, nothing stays fixed.
    /// Doubling the height doubles the bar width and the gap.
    func testEverySizeIsProportionalToTheHeight() {
        for height: CGFloat in [12, 48, 60, 120] {
            XCTAssertEqual(OuisprLogoGeometry.barWidth(forHeight: height * 2),
                           OuisprLogoGeometry.barWidth(forHeight: height) * 2, accuracy: accuracy)
            XCTAssertEqual(OuisprLogoGeometry.gap(forHeight: height * 2),
                           OuisprLogoGeometry.gap(forHeight: height) * 2, accuracy: accuracy)
        }
    }

    /// The icon's bars and gaps add up to the tallest bar (3 × 9 + 2 × 7.5 = 42),
    /// so the logo fits a square. The Live Activity's MiniLogoBars relies on this
    /// when it derives the bars from its frame width.
    func testLogoIsAsWideAsItIsTall() {
        XCTAssertEqual(OuisprLogoGeometry.logoWidth(forHeight: 60), 60, accuracy: accuracy)
    }

    /// The two call sites the issue measured, with the sizes the icon implies.
    func testCallSiteSizesMatchTheIssueTable() {
        XCTAssertEqual(OuisprLogoGeometry.barWidth(forHeight: 60), 12.857, accuracy: 0.001)
        XCTAssertEqual(OuisprLogoGeometry.gap(forHeight: 60), 10.714, accuracy: 0.001)
        XCTAssertEqual(OuisprLogoGeometry.barWidth(forHeight: 48), 10.286, accuracy: 0.001)
        XCTAssertEqual(OuisprLogoGeometry.gap(forHeight: 48), 8.571, accuracy: 0.001)
    }
}
