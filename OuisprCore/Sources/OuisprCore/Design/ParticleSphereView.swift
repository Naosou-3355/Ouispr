#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/ParticleSphereView.swift
// The particle sphere that stands for the voice assistant, drawn in a Canvas.
import SwiftUI

/// The sphere of particles: Ouispr's face for "the app is listening to you".
///
/// The maths live in `ParticleSphereSimulation`, which is tested. This view only owns
/// the clock and the drawing.
///
/// WHY a `Canvas` inside a `TimelineView` and not 1,100 SwiftUI views: a view per dot
/// would have SwiftUI diff 1,100 identities sixty times a second. A Canvas is one
/// view whose drawing is replayed, which is what this is.
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

    public var body: some View {
        // No frames while the app is not in front: iOS keeps the run loop alive for
        // the audio session, and nobody is looking.
        let paused = isPaused || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { timeline in
            let dots = driver.frame(
                at: timeline.date,
                mood: mood,
                voiceLevel: voiceLevel,
                reduceMotion: reduceMotion
            )
            Canvas { context, size in
                Self.draw(dots, in: &context, size: size)
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

    private static func draw(_ dots: [ParticleSphereDot], in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let originX = (size.width - side) / 2
        let originY = (size.height - side) / 2
        for dot in dots where dot.opacity > 0.01 {
            let radius = CGFloat(dot.radius) * side
            let rect = CGRect(
                x: originX + CGFloat(dot.x) * side - radius,
                y: originY + CGFloat(dot.y) * side - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(OuisprSphereGradient.color(at: dot.mix, opacity: dot.opacity))
            )
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
    private let points = ParticleSphereGeometry.fibonacciPoints(
        count: ParticleSphereGeometry.defaultPointCount
    )

    func wake() {
        simulation.wake()
    }

    func frame(
        at date: Date,
        mood: ParticleSphereMood,
        voiceLevel: Double,
        reduceMotion: Bool
    ) -> [ParticleSphereDot] {
        let elapsed = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        simulation.advance(
            mood: mood,
            voiceLevel: voiceLevel,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
        return simulation.dots(points: points, mood: mood, reduceMotion: reduceMotion)
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
