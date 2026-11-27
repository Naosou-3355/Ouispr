// OuisprApp/Views/InkCharacter/InkCharacterView.swift
// Ouispr's face: one ink stroke, two eyes at rest, the logo's wave while it listens.
import OuisprCore
import SwiftUI

/// The ink character chosen by Alex on the benches of 24 Nov 2026. It replaces the
/// character orb on Home and the recording screen, with the same parameters.
///
/// WHY a `Canvas` in a `TimelineView` rather than a shader: the character is at most
/// three paths of under a hundred points, rebuilt each frame from `InkCharacterDriver`.
/// Core Graphics strokes that in well under a millisecond, and a paused timeline asks
/// for no frames at all. The bench showed the browser's SVG redraw dropping about one
/// frame in forty; that cost is the browser's, not the drawing's.
///
/// Decorative: the stage is always written next to it, so VoiceOver skips it.
struct InkCharacterView: View {
    let mood: ParticleSphereMood
    var voiceLevel: Double = 0
    var isPaused: Bool = false
    /// Home's resting face: its gaze drifts and it blinks, nothing quicker, so 30 frames a
    /// second are enough; ProMotion would draw it 120 times (jank audit, 26 Nov 2026).
    var isAmbient = false

    @State private var driver: InkCharacterDriver

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// The side at which the character is drawn at the bench's size. 200 and not 240:
    /// in Home's 240 pt frame that is the bench's character 20 % larger, Alex's 1A of
    /// 25 Nov 2026 (eyes 22 pt tall, wave 128 pt wide, stroke 9.6 pt), every proportion
    /// kept.
    private static let referenceSide: CGFloat = 200

    init(mood: ParticleSphereMood, voiceLevel: Double = 0, isPaused: Bool = false, isAmbient: Bool = false,
         sharesMotion: Bool = false) {
        self.mood = mood
        self.isAmbient = isAmbient
        self.voiceLevel = voiceLevel
        self.isPaused = isPaused
        _driver = State(initialValue: sharesMotion ? InkCharacterDriver.shared : InkCharacterDriver())
    }

    var body: some View {
        if reduceMotion {
            // Under Reduce Motion each mood is a held shape, and one fades into the next
            // (Apple HIG, Motion: a dissolve in place of the movement).
            ZStack {
                character
                    .id(mood)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: Motion.standard), value: mood)
        } else {
            character
        }
    }

    private var character: some View {
        // No frames while hidden, in the background, or under Reduce Motion, where each
        // mood is shown in its held shape and redrawn only when it changes.
        let paused = isPaused || scenePhase != .active || reduceMotion
        return TimelineView(.animation(minimumInterval: isAmbient && mood == .resting ? 1.0 / 30 : nil, paused: paused)) { timeline in
            Canvas { context, size in
                let frame = driver.frame(
                    at: timeline.date.timeIntervalSinceReferenceDate,
                    mood: mood,
                    voiceLevel: voiceLevel,
                    reduceMotion: reduceMotion,
                    advancing: !paused
                )
                Self.draw(frame, in: &context, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func draw(_ frame: InkFrame, in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width, size.height) / referenceSide
        context.translateBy(x: size.width / 2, y: size.height / 2)
        context.scaleBy(x: scale, y: scale)
        drawShapes(frame, in: &context)
    }

    /// Draws a frame in a context already moved to the character's centre and scaled to
    /// its points. Shared with the model preparation screen's eyes.
    static func drawShapes(_ frame: InkFrame, in context: inout GraphicsContext) {
        InkFrameRenderer.draw(frame, in: &context)
    }
}
