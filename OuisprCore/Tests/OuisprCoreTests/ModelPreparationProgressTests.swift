// OuisprCore/Tests/OuisprCoreTests/ModelPreparationProgressTests.swift
// Pins the preparation screen's one figure, its milestones and its eyes (lot 1.1).
import XCTest
@testable import OuisprCore

final class ModelPreparationProgressTests: XCTestCase {

    private func fraction(_ phase: ModelPreparationPhase, download: Double? = nil, includesDownload: Bool = true,
                          elapsed: Double? = nil, measured: Int? = nil) -> Double {
        ModelPreparationProgress.fraction(phase: phase, downloadFraction: download, includesDownload: includesDownload,
                                          preparationElapsed: elapsed, measuredSeconds: measured)
    }

    func testTheDownloadFillsItsShareWithTheRealFraction() {
        XCTAssertEqual(fraction(.downloading), 0)
        XCTAssertEqual(fraction(.downloading, download: 0.5), 0.45, accuracy: 1e-9)
        XCTAssertEqual(fraction(.downloading, download: 1), ModelPreparationProgress.downloadShare, accuracy: 1e-9)
        XCTAssertEqual(fraction(.downloading, download: 3), ModelPreparationProgress.downloadShare, accuracy: 1e-9)
    }

    func testThePreparationStartsWhereTheDownloadEnded() {
        XCTAssertEqual(fraction(.compiling, elapsed: 0), ModelPreparationProgress.downloadShare, accuracy: 1e-9)
        XCTAssertEqual(fraction(.loading, includesDownload: false, elapsed: nil), 0, accuracy: 1e-9)
    }

    func testThePreparationNeverReadsAHundredBeforeReady() {
        for elapsed in [1.0, 30, 600, 1e6] {
            for includesDownload in [true, false] {
                let value = fraction(.compiling, includesDownload: includesDownload, elapsed: elapsed, measured: 236)
                XCTAssertLessThanOrEqual(value, ModelPreparationProgress.preparationCeiling)
                XCTAssertLessThan(ModelPreparationProgress.percent(value), 100)
            }
        }
        XCTAssertEqual(fraction(.ready), 1)
        XCTAssertEqual(ModelPreparationProgress.percent(fraction(.ready)), 100)
    }

    func testThePreparationOnlyEverMovesForward() {
        var previous = -1.0
        for step in 0...200 {
            let value = fraction(.compiling, includesDownload: false, elapsed: Double(step), measured: nil)
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
    }

    /// A measured model is about 95 % of the way through its own share when its measured
    /// time is up.
    func testAMeasuredPreparationIsNearlyDoneAtItsMeasuredTime() {
        let value = fraction(.compiling, includesDownload: false, elapsed: 236, measured: 236)
        XCTAssertEqual(value / ModelPreparationProgress.preparationCeiling, 0.95, accuracy: 0.01)
    }

    func testMilestones() {
        XCTAssertNil(ModelPreparationMilestone.reached(percent: 24, isReady: false))
        XCTAssertEqual(ModelPreparationMilestone.reached(percent: 25, isReady: false), .quarter)
        XCTAssertEqual(ModelPreparationMilestone.reached(percent: 74, isReady: false), .half)
        XCTAssertEqual(ModelPreparationMilestone.reached(percent: 99, isReady: false), .threeQuarters)
        XCTAssertEqual(ModelPreparationMilestone.reached(percent: 0, isReady: true), .done)
    }

    // MARK: - Eyes

    func testBrighteningStartsOnTheRestingEyes() {
        XCTAssertEqual(InkGeometry.brighten(0), InkGeometry.held(.resting, pose: .still))
    }

    func testBrighteningEndsOnTheLaughingEyes() {
        let end = InkGeometry.brighten(1), done = InkGeometry.held(.done, pose: .still)
        XCTAssertEqual(end.shade, done.shade)
        XCTAssertEqual(end.shapes.count, done.shapes.count)
        for (a, b) in zip(end.shapes, done.shapes) {
            guard case let .fill(outlineA) = a, case let .fill(outlineB) = b else { return XCTFail("not fills") }
            XCTAssertEqual(outlineA.count, outlineB.count)
            for (p, q) in zip(outlineA, outlineB) {
                XCTAssertEqual(p.x, q.x, accuracy: 1e-6)
                XCTAssertEqual(p.y, q.y, accuracy: 1e-6)
            }
        }
    }

    /// The dot halfway is as wide on both sides of the seam, so the passage does not jump.
    func testBrighteningIsContinuousAtItsSeam() {
        guard case let .stroke(points, width) = InkGeometry.brighten(0.4999).shapes[1],
              case let .fill(outline) = InkGeometry.brighten(0.5001).shapes[1] else { return XCTFail("shapes") }
        let xs = outline.map(\.x), ys = outline.map(\.y)
        XCTAssertEqual(width, InkGeometry.strokeWidth, accuracy: 0.01)
        XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), InkGeometry.strokeWidth, accuracy: 0.1)
        XCTAssertEqual(points[0].y, ((ys.max() ?? 0) + (ys.min() ?? 0)) / 2, accuracy: 0.1)
    }
}
