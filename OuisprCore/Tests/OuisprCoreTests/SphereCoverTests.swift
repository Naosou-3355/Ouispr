// OuisprCore/Tests/OuisprCoreTests/SphereCoverTests.swift
import XCTest
@testable import OuisprCore

@MainActor
final class SphereCoverTests: XCTestCase {
    func testStackedPresentationsKeepTheSphereCoveredUntilTheLastGoes() {
        let cover = SphereCover()
        cover.cover()
        cover.cover()
        cover.uncover()
        XCTAssertTrue(cover.isCovered)
        cover.uncover()
        XCTAssertFalse(cover.isCovered)
    }

    func testAnExtraUncoverNeverGoesNegative() {
        let cover = SphereCover()
        cover.uncover()
        XCTAssertEqual(cover.depth, 0)
        cover.cover()
        XCTAssertTrue(cover.isCovered)
    }
}
