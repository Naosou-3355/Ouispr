// OuisprCore/Tests/OuisprCoreTests/MeshSphereTests.swift
// The mesh sphere's maths: the rings cover every point, a frame stays inside its view,
// the rim is brighter than the face, and Reduce Motion freezes the drawing.
import XCTest
@testable import OuisprCore

final class MeshSphereTests: XCTestCase {

    private let geometry = MeshSphereGeometry.standard

    private func advanced(_ mood: ParticleSphereMood, voice: Double = 0, seconds: Double) -> ParticleSphereSimulation {
        var simulation = ParticleSphereSimulation(mood: mood)
        for _ in 0..<Int(seconds * 60) {
            simulation.advance(mood: mood, voiceLevel: voice, elapsed: 1.0 / 60.0, reduceMotion: false)
        }
        return simulation
    }

    func testTheRingsCoverEveryPointOnce() {
        XCTAssertEqual(geometry.rings.count, 52)
        XCTAssertEqual(geometry.rings.first?.lowerBound, 0)
        XCTAssertEqual(geometry.rings.last?.upperBound, geometry.points.count)
        for (ring, next) in zip(geometry.rings, geometry.rings.dropFirst()) {
            XCTAssertEqual(ring.upperBound, next.lowerBound)
        }
        // About 6,600 points: dense enough to read as a mesh.
        XCTAssertGreaterThan(geometry.points.count, 6_000)
        XCTAssertLessThan(geometry.points.count, 7_200)
    }

    func testThePointsSitOnTheUnitSphere() {
        for point in geometry.points {
            let length = (point.x * point.x + point.y * point.y + point.z * point.z).squareRoot()
            XCTAssertEqual(length, 1, accuracy: 1e-9)
        }
    }

    func testALoudFrameStaysInsideItsView() {
        let simulation = advanced(.listening, voice: 1, seconds: 2)
        for dark in [false, true] {
            let vertices = simulation.meshVertices(geometry: geometry, mood: .listening, reduceMotion: false, dark: dark)
            XCTAssertEqual(vertices.count, geometry.points.count)
            for vertex in vertices {
                XCTAssertTrue((0...1).contains(vertex.x))
                XCTAssertTrue((0...1).contains(vertex.y))
                XCTAssertTrue((0...1).contains(vertex.opacity))
                XCTAssertTrue((0...1).contains(vertex.mix))
            }
        }
    }

    func testTheRimIsBrighterThanTheFace() {
        let vertices = advanced(.resting, seconds: 1)
            .meshVertices(geometry: geometry, mood: .resting, reduceMotion: false, dark: false)
        let rim = vertices.filter { $0.rim > 0.8 }
        let face = vertices.filter { $0.rim < 0.05 }
        XCTAssertFalse(rim.isEmpty)
        XCTAssertFalse(face.isEmpty)
        let average = { (list: [MeshSphereVertex]) in list.map(\.opacity).reduce(0, +) / Double(list.count) }
        XCTAssertGreaterThan(average(rim), average(face) * 3)
    }

    func testReduceMotionFreezesTheDrawing() {
        let early = advanced(.resting, seconds: 0.5)
        let late = advanced(.resting, seconds: 3)
        let first = early.meshVertices(geometry: geometry, mood: .resting, reduceMotion: true, dark: false)
        let second = late.meshVertices(geometry: geometry, mood: .resting, reduceMotion: true, dark: false)
        XCTAssertEqual(first, second)
    }

    func testThePaletteRunsFromBlueToPink() {
        let blue = MeshSphereStyle.rgb(at: 0, opacityBand: 0.5, dark: false)
        XCTAssertEqual(blue.red, Double(0x2F) / 255, accuracy: 1e-9)
        XCTAssertEqual(blue.blue, 1, accuracy: 1e-9)
        let pink = MeshSphereStyle.rgb(at: 1, opacityBand: 0.5, dark: false)
        XCTAssertEqual(pink.red, Double(0xC8) / 255, accuracy: 1e-9)
        // In dark mode the brightest band glows toward lilac.
        let glow = MeshSphereStyle.rgb(at: 0, opacityBand: 0.95, dark: true)
        XCTAssertGreaterThan(glow.red, blue.red)
    }
}
