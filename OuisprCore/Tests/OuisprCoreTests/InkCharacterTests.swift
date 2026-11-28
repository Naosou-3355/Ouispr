// OuisprCore/Tests/OuisprCoreTests/InkCharacterTests.swift
// The ink character: validated sizes, no jump at either end of a passage, and moods
// reached through the right passages, interrupted or not.
import XCTest
@testable import OuisprCore

final class InkCharacterTests: XCTestCase {
    private struct Box: Equatable {
        var minX, minY, maxX, maxY: Double
    }

    /// Everything the ink covers, strokes widened by half their width.
    private func box(_ frame: InkFrame) -> Box {
        var box = Box(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity)
        func add(_ p: InkPoint, _ pad: Double) {
            box.minX = min(box.minX, p.x - pad); box.maxX = max(box.maxX, p.x + pad)
            box.minY = min(box.minY, p.y - pad); box.maxY = max(box.maxY, p.y + pad)
        }
        for shape in frame.shapes {
            switch shape {
            case let .stroke(points, width): points.forEach { add($0, width / 2) }
            case let .fill(outline): outline.forEach { add($0, 0) }
            }
        }
        return box
    }

    private func assertClose(_ a: InkFrame, _ b: InkFrame, within tolerance: Double = 1, _ label: String) {
        let ba = box(a), bb = box(b)
        for (x, y) in [(ba.minX, bb.minX), (ba.maxX, bb.maxX), (ba.minY, bb.minY), (ba.maxY, bb.maxY)] {
            XCTAssertEqual(x, y, accuracy: tolerance, label)
        }
        XCTAssertEqual(a.shade, b.shade, accuracy: 0.02, label)
    }

    private let pose = InkPose.still

    // MARK: - Sizes validated on the bench

    func testWaveIsAbout107PointsWideWithAnEightPointStroke() {
        let frame = InkGeometry.held(.listening, pose: pose)
        guard case let .stroke(points, width) = frame.shapes.first else { return XCTFail("one stroke") }
        XCTAssertEqual(frame.shapes.count, 1)
        XCTAssertEqual(width, 8, accuracy: 0.01)
        XCTAssertEqual(points.last!.x - points.first!.x, 107, accuracy: 1) // swiftlint:disable:this force_unwrapping
        XCTAssertEqual(frame.shade, 1)
    }

    func testRestShowsTwoEyes38PointsApartInEvenInk() {
        let frame = InkGeometry.held(.resting, pose: pose)
        XCTAssertEqual(frame.shapes.count, 2)
        XCTAssertEqual(frame.shade, 0)
        guard case let .stroke(left, width) = frame.shapes[0], case let .stroke(right, _) = frame.shapes[1] else {
            return XCTFail("two strokes")
        }
        XCTAssertEqual(right[0].x - left[0].x, 37.8, accuracy: 0.5)
        XCTAssertEqual(width, 9.72, accuracy: 0.01)
        XCTAssertEqual(left[1].y - left[0].y, 18, accuracy: 0.01)
    }

    func testDoneShowsTwoFilledLaughingEyes() {
        let frame = InkGeometry.held(.done, pose: pose)
        XCTAssertEqual(frame.shapes.count, 2)
        for shape in frame.shapes {
            guard case .fill = shape else { return XCTFail("laughing eyes are filled ribbons") }
        }
    }

    // MARK: - No jump at either end of a passage

    func testArchStartsOnTheEyesAndEndsOnTheWave() {
        let wave: (Double) -> Double = { InkGeometry.wave($0, self.pose) }
        assertClose(InkGeometry.arch(0, gazeX: 0, gazeY: 0, line: wave), InkGeometry.held(.resting, pose: pose), "arch start")
        assertClose(InkGeometry.arch(1, gazeX: 0, gazeY: 0, line: wave), InkGeometry.held(.listening, pose: pose), "arch end")
    }

    func testArchStartsWhereTheGazeLeftTheEyes() {
        let wave: (Double) -> Double = { InkGeometry.wave($0, self.pose) }
        assertClose(
            InkGeometry.arch(0, gazeX: 0.2, gazeY: -0.1, line: wave),
            InkGeometry.held(.resting, pose: pose, gazeX: 0.2, gazeY: -0.1),
            "arch start, eyes looking aside"
        )
    }

    func testCalmEndsOnTheBreathingCrest() {
        assertClose(InkGeometry.calm(0, pose: pose), InkGeometry.held(.listening, pose: pose), "calm start")
        assertClose(InkGeometry.calm(1, pose: pose), InkGeometry.held(.working, pose: pose), "calm end")
    }

    func testDropGoesFromTheCrestToTheLaughingEyes() {
        assertClose(InkGeometry.drop(0, pose: pose), InkGeometry.held(.working, pose: pose), "drop start")
        assertClose(InkGeometry.drop(1, pose: pose), InkGeometry.held(.done, pose: pose), within: 0.5, "drop end")
    }

    func testWakeGoesFromTheLaughingEyesToOpenEyes() {
        assertClose(InkGeometry.wake(0), InkGeometry.held(.done, pose: pose), "wake start")
        assertClose(InkGeometry.wake(1), InkGeometry.held(.resting, pose: pose), "wake end")
    }

    func testCancelledWorkFoldsBackIntoEyes() {
        let crest: (Double) -> Double = { InkGeometry.bump($0, self.pose) }
        let back = { (tau: Double) in
            InkGeometry.arch(tau, gazeX: 0, gazeY: 0, lineHalf: 0.6 * InkGeometry.halfLength, line: crest)
        }
        assertClose(back(1), InkGeometry.held(.working, pose: pose), "from the crest")
        assertClose(back(0), InkGeometry.held(.resting, pose: pose), "to the eyes")
    }

    /// Small steps through every passage never move the ink's extent by much: no frame
    /// pops.
    func testEveryPassageMovesSmoothly() {
        let wave: (Double) -> Double = { InkGeometry.wave($0, self.pose) }
        let passages: [(String, (Double) -> InkFrame)] = [
            ("arch", { InkGeometry.arch($0, gazeX: 0, gazeY: 0, line: wave) }),
            ("calm", { InkGeometry.calm($0, pose: self.pose) }),
            ("drop", { InkGeometry.drop($0, pose: self.pose) }),
            ("wake", { InkGeometry.wake($0) })
        ]
        for (name, passage) in passages {
            var previous = box(passage(0))
            for step in 1...240 {
                let current = box(passage(Double(step) / 240))
                let moves = [current.minX - previous.minX, current.maxX - previous.maxX,
                             current.minY - previous.minY, current.maxY - previous.maxY]
                XCTAssertLessThan(moves.map(abs).max() ?? 0, 4, "\(name) jumps at step \(step)")
                previous = current
            }
        }
    }

    // MARK: - The driver

    private func run(_ driver: InkCharacterDriver, _ mood: ParticleSphereMood, from start: Double, for seconds: Double,
                     reduceMotion: Bool = false, seen: inout Set<String>) -> Double {
        var time = start
        while time < start + seconds {
            time += 1.0 / 120
            _ = driver.frame(at: time, mood: mood, voiceLevel: 0.5, reduceMotion: reduceMotion)
            seen.insert("\(driver.settled)")
        }
        return time
    }

    func testAFullDictationGoesThroughEveryMood() {
        let driver = InkCharacterDriver()
        var seen = Set<String>()
        var time = run(driver, .resting, from: 0, for: 0.5, seen: &seen)
        time = run(driver, .listening, from: time, for: 1.2, seen: &seen)
        XCTAssertEqual(driver.settled, .listening)
        time = run(driver, .working, from: time, for: 1, seen: &seen)
        XCTAssertEqual(driver.settled, .working)
        time = run(driver, .done, from: time, for: 1, seen: &seen)
        XCTAssertEqual(driver.settled, .done)
        _ = run(driver, .resting, from: time, for: 1, seen: &seen)
        XCTAssertEqual(driver.settled, .resting)
        XCTAssertFalse(driver.isMoving)
    }

    func testCancellingWhileTheEyesOpenGoesBackToRestWithoutLaughing() {
        let driver = InkCharacterDriver()
        var seen = Set<String>()
        var time = run(driver, .listening, from: 0, for: 0.3, seen: &seen)
        XCTAssertTrue(driver.isMoving)
        time = run(driver, .resting, from: time, for: 1.5, seen: &seen)
        XCTAssertEqual(driver.settled, .resting)
        XCTAssertFalse(seen.contains("done"))
        XCTAssertFalse(seen.contains("working"))
    }

    func testAQuickTranscriptionHurriesThroughTheCalm() {
        let driver = InkCharacterDriver()
        var seen = Set<String>()
        var time = run(driver, .listening, from: 0, for: 1.2, seen: &seen)
        time = run(driver, .working, from: time, for: 0.1, seen: &seen)
        // Done arrives mid-calm: the calm speeds up, then the drop plays at its pace.
        time = run(driver, .done, from: time, for: 1.3, seen: &seen)
        XCTAssertEqual(driver.settled, .done)
    }

    func testReduceMotionShowsEachMoodAtOnce() {
        let driver = InkCharacterDriver()
        var seen = Set<String>()
        _ = run(driver, .listening, from: 0, for: 1.0 / 60, reduceMotion: true, seen: &seen)
        XCTAssertEqual(driver.settled, .listening)
        XCTAssertFalse(driver.isMoving)
    }

    func testAPausedViewUnderReduceMotionStillShowsTheNewMood() {
        let driver = InkCharacterDriver()
        let frame = driver.frame(at: 1, mood: .working, voiceLevel: 0, reduceMotion: true, advancing: false)
        let held = InkGeometry.held(.working, pose: InkPose(levels: [0, 0, 0], phase: 0, clock: 0))
        XCTAssertEqual(frame.shapes, held.shapes)
    }

    func testAPausedViewLeavesTheSharedDriverAlone() {
        let driver = InkCharacterDriver()
        var seen = Set<String>()
        _ = run(driver, .listening, from: 0, for: 1.2, seen: &seen)
        let settled = driver.settled
        _ = driver.frame(at: 5, mood: .resting, voiceLevel: 0, reduceMotion: true, advancing: false)
        XCTAssertEqual(driver.settled, settled)
        XCTAssertFalse(driver.isMoving)
    }

    func testHomeAskingForRestDoesNotUndoTheRecordingScreensResult() {
        let driver = InkCharacterDriver()
        var seen = Set<String>()
        var time = run(driver, .listening, from: 0, for: 1.2, seen: &seen)
        time = run(driver, .working, from: time, for: 1, seen: &seen)
        time = run(driver, .done, from: time, for: 1, seen: &seen)
        // Both screens draw the same frames: the recording screen shows the result,
        // Home asks for rest.
        for _ in 0..<60 {
            time += 1.0 / 120
            _ = driver.frame(at: time, mood: .done, voiceLevel: 0, reduceMotion: false)
            _ = driver.frame(at: time, mood: .resting, voiceLevel: 0, reduceMotion: false)
        }
        XCTAssertEqual(driver.settled, .done)
        XCTAssertFalse(driver.isMoving)
    }

    /// A paused screen shows open eyes looking ahead, whatever frame the clock stopped
    /// on (audit of 26 Nov 2026, n°21).
    func testPausedRestIsAlwaysTheHeldEyes() {
        let held = InkGeometry.held(.resting, pose: InkPose(levels: [0, 0, 0], phase: 0, clock: 0)).shapes
        // Stopped at many moments, some of them mid-blink or mid-glance.
        for stop in stride(from: 2.0, through: 8.0, by: 0.05) {
            let driver = InkCharacterDriver()
            var time = 0.0
            while time < stop {
                time += 1.0 / 60
                _ = driver.frame(at: time, mood: .resting, voiceLevel: 0, reduceMotion: false)
            }
            let paused = driver.frame(at: time, mood: .resting, voiceLevel: 0, reduceMotion: false, advancing: false)
            XCTAssertEqual(paused.shapes, held, "stopped at \(stop) s")
        }
    }

    func testADriverSettledInListeningStartsOnTheWaveWithNoArch() {
        // Lot 1.8: the keyboard's listening screen and the « J'écoute » hand-off start on
        // the wave; a fresh driver would spend 0.9 s opening from the eyes first.
        let driver = InkCharacterDriver(settledIn: .listening)
        let first = driver.frame(at: 0, mood: .listening, voiceLevel: 0, reduceMotion: false)
        let next = driver.frame(at: 0.05, mood: .listening, voiceLevel: 0, reduceMotion: false)
        for frame in [first, next] {
            XCTAssertEqual(frame.shapes.count, 1, "one stroke: the wave, not two eyes")
            XCTAssertEqual(frame.shade, 1)
        }
        XCTAssertFalse(driver.isMoving)
    }

    func testTheWaveRisesWithTheVoice() {
        func height(voice: Double) -> Double {
            let driver = InkCharacterDriver(settledIn: .listening)
            var frame = driver.frame(at: 0, mood: .listening, voiceLevel: voice, reduceMotion: false)
            for step in 1...60 {
                frame = driver.frame(at: Double(step) / 60, mood: .listening, voiceLevel: voice, reduceMotion: false)
            }
            guard case let .stroke(points, _) = frame.shapes.first else { return 0 }
            return points.map { abs($0.y) }.max() ?? 0
        }
        XCTAssertGreaterThan(height(voice: 0.8), 2 * height(voice: 0))
    }
}

