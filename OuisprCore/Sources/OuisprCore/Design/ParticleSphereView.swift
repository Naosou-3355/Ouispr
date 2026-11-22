#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/ParticleSphereView.swift
// The mesh sphere that stands for the voice assistant, drawn in a Canvas.
import SwiftUI

/// The sphere of particles: Ouispr's face for "the app is listening to you".
///
/// The maths live in `ParticleSphereSimulation` and `MeshSphere.swift`, which are
/// tested. This view only owns the clock and the drawing. Since bench 5 (21 Nov 2026)
/// it draws the mesh: about 6,600 fine points on rings, lit on the rim, with faint
/// wires along the rings where the surface turns away.
///
/// WHY a `Canvas` inside a `TimelineView` and not thousands of SwiftUI views: a view
/// per point would have SwiftUI diff thousands of identities sixty times a second. A
/// Canvas is one view whose drawing is replayed, which is what this is.
///
/// Decorative: the stage is always written next to it ("Listening", "Cleaning up"),
/// so VoiceOver skips the sphere and reads the label.
public struct ParticleSphereView: View {
    private let mood: ParticleSphereMood
    private let voiceLevel: Double
    private let isPaused: Bool

    @State private var driver = ParticleSphereDriver()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - mood: what the sphere is saying.
    ///   - voiceLevel: the microphone level, 0 to 1. Only read while listening.
    ///   - isPaused: true when something covers the sphere. A paused sphere stops
    ///     asking for frames, which is what keeps a hidden one from costing battery.
    public init(mood: ParticleSphereMood, voiceLevel: Double = 0, isPaused: Bool = false) {
        self.mood = mood
        self.voiceLevel = voiceLevel
        self.isPaused = isPaused
    }

    /// 30 frames a second at rest, 60 while the sphere answers the voice or works.
    ///
    /// WHY: the resting sphere is on screen whenever Home is, and turns slowly enough
    /// that 30 frames read as smooth. It halves the cost of the screen people see most
    /// (about a third of a core at 60 on the simulator, 22 Nov 2026).
    private var frameInterval: Double {
        mood == .resting ? 1.0 / 30.0 : 1.0 / 60.0
    }

    public var body: some View {
        // No frames while the app is not in front: iOS keeps the run loop alive for
        // the audio session, and nobody is looking.
        let paused = isPaused || scenePhase != .active
        TimelineView(.animation(minimumInterval: frameInterval, paused: paused)) { timeline in
            let dark = colorScheme == .dark
            let vertices = driver.frame(
                at: timeline.date,
                mood: mood,
                voiceLevel: voiceLevel,
                reduceMotion: reduceMotion,
                dark: dark
            )
            Canvas { context, size in
                MeshSphereRenderer.draw(
                    vertices,
                    rings: driver.geometry.rings,
                    dark: dark,
                    in: &context,
                    size: size
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(halo)
        .onChange(of: mood) { oldMood, newMood in
            // Bench 4: the sphere wakes with one small bounce when listening starts.
            if newMood == .listening, oldMood != .listening {
                driver.wake()
            }
        }
        .accessibilityHidden(true)
    }

    /// A light halo behind the sphere (bench 2), wider than the sphere itself.
    private var halo: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            RadialGradient(
                colors: [Color.ouisprSphereEnd.opacity(0.20), Color.ouisprSphereEnd.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: side * 0.52
            )
            // Larger than the sphere's own frame: a background is not clipped, and the
            // halo has to fade out past the outermost dots, not at the frame's edge.
            .frame(width: side * 1.44, height: side * 1.44)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

/// Draws a mesh frame.
///
/// WHY buckets: a `Canvas` fill or stroke costs the same for one shape or a thousand
/// in one path, but each needs a single colour. The points are sorted into 10 colour
/// bands times 10 opacity bands, so a frame is at most 200 fills and strokes instead
/// of thousands.
private enum MeshSphereRenderer {
    private static let colourBands = 10
    private static let opacityBands = 10

    private static func band(colour: Double, opacity: Double) -> Int {
        let colourIndex = min(colourBands - 1, max(0, Int(colour * Double(colourBands))))
        let opacityIndex = min(opacityBands - 1, max(0, Int(opacity * Double(opacityBands) * 0.999)))
        return colourIndex * opacityBands + opacityIndex
    }

    private static func color(band: Int, maximumOpacity: Double, dark: Bool) -> Color {
        let colourFraction = (Double(band / opacityBands) + 0.5) / Double(colourBands)
        let opacityFraction = (Double(band % opacityBands) + 0.5) / Double(opacityBands)
        let rgb = MeshSphereStyle.rgb(at: colourFraction, opacityBand: opacityFraction, dark: dark)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacityFraction * maximumOpacity)
    }

    static func draw(
        _ vertices: [MeshSphereVertex],
        rings: [Range<Int>],
        dark: Bool,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard !vertices.isEmpty else { return }
        let side = min(size.width, size.height)
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        func point(_ vertex: MeshSphereVertex) -> CGPoint {
            CGPoint(x: originX + CGFloat(vertex.x) * side, y: originY + CGFloat(vertex.y) * side)
        }
        // In dark mode the points add light to the background, which is what makes the
        // rim glow; on a light background they are laid on top as usual.
        if dark { context.blendMode = .plusLighter }

        // Wires first, under the points: segments between neighbours on a ring, faded
        // where the surface faces the viewer.
        var wires = [Path](repeating: Path(), count: colourBands * opacityBands)
        for ring in rings where ring.count > 1 {
            for index in ring {
                let next = index + 1 < ring.upperBound ? index + 1 : ring.lowerBound
                let first = vertices[index], second = vertices[next]
                let rim = (first.rim + second.rim) / 2
                let opacity = (first.opacity + second.opacity) / 2 * (0.15 + 0.85 * rim)
                guard opacity >= MeshSphereStyle.wireThreshold else { continue }
                let bucket = band(colour: (first.mix + second.mix) / 2, opacity: opacity)
                wires[bucket].move(to: point(first))
                wires[bucket].addLine(to: point(second))
            }
        }
        let wireWidth = max(0.5, side * MeshSphereStyle.wireFraction)
        for (bucket, path) in wires.enumerated() where !path.isEmpty {
            context.stroke(
                path,
                with: .color(color(band: bucket, maximumOpacity: dark ? 0.5 : 0.55, dark: dark)),
                lineWidth: wireWidth
            )
        }

        // Then the points, as tiny squares: at this size a square and a disc look the
        // same, and a square is cheaper to fill.
        let dot = max(0.5, side * MeshSphereStyle.dotFraction * (dark ? 1.05 : 1))
        var dots = [Path](repeating: Path(), count: colourBands * opacityBands)
        for vertex in vertices where vertex.opacity > 0.01 {
            let centre = point(vertex)
            dots[band(colour: vertex.mix, opacity: vertex.opacity)]
                .addRect(CGRect(x: centre.x - dot / 2, y: centre.y - dot / 2, width: dot, height: dot))
        }
        for (bucket, path) in dots.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(color(band: bucket, maximumOpacity: 1, dark: dark)))
        }
    }
}

/// Holds the simulation between frames.
///
/// WHY a class in `@State` and not the struct itself: a frame is computed while the
/// view's body runs, and writing a `@State` value there asks SwiftUI for another body
/// pass, which would be a loop. A reference lets each frame advance the simulation
/// without publishing anything. The timeline is what asks for the next frame.
private final class ParticleSphereDriver {
    private var simulation = ParticleSphereSimulation()
    private var lastDate: Date?
    let geometry = MeshSphereGeometry.standard

    func wake() {
        simulation.wake()
    }

    func frame(
        at date: Date,
        mood: ParticleSphereMood,
        voiceLevel: Double,
        reduceMotion: Bool,
        dark: Bool
    ) -> [MeshSphereVertex] {
        let elapsed = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        simulation.advance(
            mood: mood,
            voiceLevel: voiceLevel,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
        return simulation.meshVertices(
            geometry: geometry,
            mood: mood,
            reduceMotion: reduceMotion,
            dark: dark
        )
    }
}

#Preview("Resting") {
    ParticleSphereView(mood: .resting)
        .frame(width: 240, height: 240)
        .padding(60)
        .background(Color.ouisprBackground)
}

#Preview("Listening") {
    ParticleSphereView(mood: .listening, voiceLevel: 0.6)
        .frame(width: 200, height: 200)
        .padding(60)
        .background(Color.ouisprBackground)
}
#endif
