// OuisprCore/Tests/OuisprCoreTests/ParticleSphereTests.swift
// The particle sphere's maths: the points sit on a sphere, a frame stays inside its
// view, a kick settles, and Reduce Motion stops the motion.
import XCTest
@testable import OuisprCore

final class ParticleSphereTests: XCTestCase {

    private let points = ParticleSphereGeometry.fibonacciPoints(
        count: ParticleSphereGeometry.defaultPointCount
    )

    /// Runs `seconds` of simulation at sixty frames a second.
    private func run(
        _ simulation: inout ParticleSphereSimulation,
        mood: ParticleSphereMood,
        voiceLevel: Double = 0,
        seconds: Double,
        reduceMotion: Bool = false
    ) {
        let frames = Int((seconds * 60).rounded())
        for _ in 0..<frames {
            simulation.advance(mood: mood, voiceLevel: voiceLevel, elapsed: 1.0 / 60.0, reduceMotion: reduceMotion)
        }
    }

    // MARK: - Geometry

    func testThePointsSitOnTheUnitSphere() {
        XCTAssertEqual(points.count, 1100)
        for point in points {
            let length = (point.x * point.x + point.y * point.y + point.z * point.z).squareRoot()
            XCTAssertEqual(length, 1, accuracy: 1e-9)
        }
    }

    func testThePointsCoverBothHalvesEvenly() {
        let upper = points.filter { $0.y > 0 }.count
        XCTAssertEqual(upper, points.count / 2)
        let front = points.filter { $0.z > 0 }.count
        XCTAssertEqual(Double(front), Double(points.count) / 2, accuracy: Double(points.count) * 0.02)
    }

    func testNoPointsForANonPositiveCount() {
        XCTAssertTrue(ParticleSphereGeometry.fibonacciPoints(count: 0).isEmpty)
        XCTAssertTrue(ParticleSphereGeometry.fibonacciPoints(count: -3).isEmpty)
    }

    // MARK: - Frames

    /// The loudest voice on the most rippled mood, mid-bounce: the worst case for a
    /// dot leaving the view.
    func testEveryDotStaysInsideTheView() {
        var simulation = ParticleSphereSimulation()
        simulation.wake()
        for frame in 0..<240 {
            simulation.advance(mood: .listening, voiceLevel: 1, elapsed: 1.0 / 60.0, reduceMotion: false)
            let dots = simulation.dots(points: points, mood: .listening, reduceMotion: false)
            XCTAssertEqual(dots.count, points.count)
            for dot in dots {
                XCTAssertGreaterThanOrEqual(dot.x - dot.radius, 0, "frame \(frame)")
                XCTAssertLessThanOrEqual(dot.x + dot.radius, 1, "frame \(frame)")
                XCTAssertGreaterThanOrEqual(dot.y - dot.radius, 0, "frame \(frame)")
                XCTAssertLessThanOrEqual(dot.y + dot.radius, 1, "frame \(frame)")
                XCTAssertGreaterThanOrEqual(dot.opacity, 0)
                XCTAssertLessThanOrEqual(dot.opacity, 1)
                XCTAssertGreaterThanOrEqual(dot.mix, 0)
                XCTAssertLessThanOrEqual(dot.mix, 1)
            }
        }
    }

    func testFrontDotsAreLargerAndMoreOpaqueThanBackDots() {
        let simulation = ParticleSphereSimulation()
        let dots = simulation.dots(points: points, mood: .resting, reduceMotion: false)
        let largest = dots.max { $0.radius < $1.radius }
        let smallest = dots.min { $0.radius < $1.radius }
        XCTAssertNotNil(largest)
        XCTAssertNotNil(smallest)
        XCTAssertGreaterThan(largest?.opacity ?? 0, 0.8)
        XCTAssertLessThan(smallest?.opacity ?? 1, 0.1)
    }

    // MARK: - Motion

    func testTheSphereTurnsAtRest() {
        var simulation = ParticleSphereSimulation()
        run(&simulation, mood: .resting, seconds: 1)
        XCTAssertEqual(simulation.angle, 0.7, accuracy: 0.02)
    }

    func testAMoodChangeEasesInsteadOfSnapping() {
        var simulation = ParticleSphereSimulation()
        simulation.advance(mood: .done, voiceLevel: 0, elapsed: 1.0 / 60.0, reduceMotion: false)
        XCTAssertGreaterThan(simulation.current.rotationSpeed, 0.6)
        run(&simulation, mood: .done, seconds: 3)
        XCTAssertEqual(simulation.current.rotationSpeed, 0.1, accuracy: 0.01)
    }

    func testTheWakeBouncesOnceThenSettles() {
        var simulation = ParticleSphereSimulation()
        simulation.wake()
        XCTAssertEqual(simulation.scale, 0.88, accuracy: 1e-9)

        var highest = simulation.scale
        for _ in 0..<120 {
            simulation.advance(mood: .listening, voiceLevel: 0, elapsed: 1.0 / 60.0, reduceMotion: false)
            highest = max(highest, simulation.scale)
        }
        // It overshoots, which is the bounce, but only slightly.
        XCTAssertGreaterThan(highest, 1.0)
        XCTAssertLessThan(highest, 1.06)
        XCTAssertEqual(simulation.scale, 1, accuracy: 0.002)
    }

    func testALateFrameDoesNotFlingTheSpring() {
        var simulation = ParticleSphereSimulation()
        simulation.wake()
        // Ten seconds in one step, as after a return from the background.
        simulation.advance(mood: .listening, voiceLevel: 0, elapsed: 10, reduceMotion: false)
        XCTAssertGreaterThan(simulation.scale, 0.8)
        XCTAssertLessThan(simulation.scale, 1.2)
    }

    func testTheVoiceLevelIsClampedAndFollowed() {
        var simulation = ParticleSphereSimulation()
        run(&simulation, mood: .listening, voiceLevel: 7, seconds: 1)
        XCTAssertEqual(simulation.level, 1, accuracy: 0.01)
        run(&simulation, mood: .listening, voiceLevel: -2, seconds: 2)
        XCTAssertEqual(simulation.level, 0, accuracy: 0.01)
    }

    // MARK: - Reduce Motion

    func testReduceMotionStopsTheRotationAndTheBounce() {
        var simulation = ParticleSphereSimulation()
        simulation.wake()
        run(&simulation, mood: .listening, voiceLevel: 1, seconds: 2, reduceMotion: true)
        XCTAssertEqual(simulation.angle, 0)
        XCTAssertEqual(simulation.scale, 1)

        let first = simulation.dots(points: points, mood: .resting, reduceMotion: true)
        run(&simulation, mood: .resting, seconds: 1, reduceMotion: true)
        let second = simulation.dots(points: points, mood: .resting, reduceMotion: true)
        XCTAssertEqual(first.map(\.x), second.map(\.x))
        XCTAssertEqual(first.map(\.y), second.map(\.y))
    }

    func testReduceMotionMakesTheBrightnessFollowTheVoice() {
        var quiet = ParticleSphereSimulation()
        run(&quiet, mood: .listening, voiceLevel: 0, seconds: 1, reduceMotion: true)
        var loud = ParticleSphereSimulation()
        run(&loud, mood: .listening, voiceLevel: 1, seconds: 1, reduceMotion: true)

        let quietOpacity = quiet.dots(points: points, mood: .listening, reduceMotion: true).map(\.opacity).reduce(0, +)
        let loudOpacity = loud.dots(points: points, mood: .listening, reduceMotion: true).map(\.opacity).reduce(0, +)
        XCTAssertGreaterThan(loudOpacity, quietOpacity * 1.5)
    }
}
