// OuisprApp/Views/ModelPreparationParts.swift
// The pieces of the model preparation screen: its spacing, and the character whose eyes
// fill with ink as the model gets ready. Lot 1.1 (Alex's bench of 27 Nov 2026).
import SwiftUI
import OuisprCore

/// Spacing of the preparation screen, on the 8 pt grid (lot 1.3).
///
/// One block on one vertical axis, top to bottom: the eyes, 8, the figure, 4, the status
/// line that goes with it, 40, the title, 8, the subtitle. The figure and its status are
/// one reading, so they touch; the 40 pt gap separates what the screen measures from what
/// it says.
enum ModelPreparationMetrics {
    static let faceToPercent: CGFloat = 8
    static let percentToStatus: CGFloat = 4
    static let statusToTitle: CGFloat = 40
    static let titleToSubtitle: CGFloat = 8
    /// The subtitle's measure: two balanced lines rather than one long and one short.
    static let subtitleWidth: CGFloat = 300
    /// Where the block's centre sits, as a fraction of the height it has (lot 1.3).
    static let opticalCentre: CGFloat = 0.45
    /// The least room above the block and between it and the notice.
    static let minimumMargin: CGFloat = 24
    /// The notice at the foot of the screen, above the home indicator.
    static let footerBottom: CGFloat = 16
    /// Beyond this the lines get too long to read in one glance (an iPad, a landscape phone).
    static let maxTextWidth: CGFloat = 440
}

// MARK: - Face

/// The ink character's two eyes, filled from the bottom with the preparation's progress,
/// alive as laughing eyes once the model is ready (lot 1.1, « Les yeux se remplissent »).
///
/// WHY THE SAME SIZE AS ON HOME: the screen introduces the character the user then meets
/// on Home. Home draws it at 1.2 times the bench's size (`InkCharacterView`, 240 pt
/// frame), so these eyes are drawn at the same scale, every proportion
/// from `InkGeometry`. The frame is cut close around the eyes, so the percentage sits
/// right under them.
///
/// - Filling: each eye is a capsule outline, thin and at 55 % of the ink, and the ink
///   rises inside it. A change of figure eases over 0.35 s rather than stepping. The
///   gaze drifts a little, slowly, as on the bench, so a long compile does not look
///   frozen.
/// - Ready: the full eyes come alive (`InkGeometry.brighten`), driven by a spring that
///   does not overshoot (0.45 s, Alex: « attention à la transition, il faut que ce soit
///   fluide »). The drift eases back to the centre during it, so nothing jumps.
/// - Reduce Motion: no drift, the ink stands at its level, the laughing eyes fade in.
struct ModelPreparationFace: View {
    /// The preparation's progress, 0 to 1.
    let fraction: Double
    let isReady: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var fill = FillTween()
    /// When the eyes started coming alive. `.distantPast` for a screen opened on a model
    /// already ready: nothing to watch, the eyes laugh from the first frame.
    @State private var readyAt: Date?
    /// Where the drift had taken the eyes when they started coming alive.
    @State private var readyGaze = 0.0
    /// True while the passage runs, so it is drawn at the display's full rate.
    @State private var isBrightening = false

    /// Home's scale: 240 / 200 (`InkCharacterView.referenceSide`).
    static let scale: CGFloat = 1.2
    /// Cut close around the eyes and their laughing arcs.
    static let size = CGSize(width: 104, height: 40)
    fileprivate static let fillDuration = 0.35
    private static let brightenResponse = 0.45
    /// The bench's outline: 1.6 pt in the character's space, 55 % of the ink.
    private static let outlineWidth = 1.6
    private static let outlineOpacity = 0.55
    /// The bench's drift: 0.12 of the gaze's reach, one swing in about 20 s.
    private static let driftAmplitude = 0.12 * 0.16 * 180
    private static let driftSpeed = 0.31

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    Canvas { context, size in
                        draw(level: fraction, offset: 0, in: &context, size: size)
                    }
                    .opacity(isReady ? 0 : 1)
                    Canvas { context, size in
                        Self.prepare(&context, size: size)
                        InkCharacterView.drawShapes(InkGeometry.brighten(1), in: &context)
                    }
                    .opacity(isReady ? 1 : 0)
                }
                .animation(.easeOut(duration: Motion.standard), value: isReady)
            } else {
                // 30 frames a second are plenty for a level easing and a slow drift; the
                // passage to laughing eyes gets the full rate.
                TimelineView(.animation(minimumInterval: isBrightening ? nil : 1.0 / 30,
                                        paused: scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        let date = timeline.date
                        if let readyAt, date >= readyAt {
                            let tau = springProgress(date.timeIntervalSince(readyAt))
                            Self.prepare(&context, size: size)
                            context.translateBy(x: readyGaze * (1 - tau), y: 0)
                            InkCharacterView.drawShapes(InkGeometry.brighten(tau), in: &context)
                        } else if let readyAt {
                            // The drift is held where it will be when the passage starts.
                            let offset = Self.drift(at: min(date, readyAt))
                            draw(level: fill.level(at: date), offset: offset, in: &context, size: size)
                        } else {
                            draw(level: fill.level(at: date), offset: Self.drift(at: date), in: &context, size: size)
                        }
                    }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The percentage under it says the same thing, and VoiceOver reads it there.
        .accessibilityHidden(true)
        .onChange(of: fraction, initial: true) { _, newValue in
            fill = fill.retargeted(to: newValue, at: Date())
        }
        .onChange(of: isReady, initial: true) { oldValue, ready in
            guard ready, readyAt == nil else { return }
            // `initial: true` passes the same value twice on the first call: a screen
            // that opens on a ready model.
            if oldValue == ready {
                readyAt = .distantPast
                return
            }
            // The ink first rises to the top, then the full eyes come alive: the passage
            // starts from full eyes, so a fill left below full would pop to it.
            let now = Date()
            fill = fill.retargeted(to: 1, at: now)
            readyAt = now.addingTimeInterval(Self.fillDuration)
            readyGaze = reduceMotion ? 0 : Self.drift(at: now.addingTimeInterval(Self.fillDuration))
            isBrightening = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                isBrightening = false
            }
        }
    }

    private static func drift(at date: Date) -> Double {
        driftAmplitude * sin(date.timeIntervalSinceReferenceDate * driftSpeed)
    }

    /// 0 → 1 along a critically damped spring: quick, settling, never past 1.
    private func springProgress(_ elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega = 2 * Double.pi / Self.brightenResponse
        return min(1, 1 - exp(-omega * elapsed) * (1 + omega * elapsed))
    }

    /// Moves the context to the eyes' centre, at the character's scale.
    private static func prepare(_ context: inout GraphicsContext, size: CGSize) {
        context.translateBy(x: size.width / 2, y: size.height / 2 - InkGeometry.eyeCentre.y * scale)
        context.scaleBy(x: scale, y: scale)
    }

    private func draw(level: Double, offset: Double, in context: inout GraphicsContext, size: CGSize) {
        Self.prepare(&context, size: size)
        let ink = Color.ouisprInk
        let radius = InkGeometry.eyeWidth / 2
        let height = 2 * InkGeometry.eyeStrokeHalfLength + InkGeometry.eyeWidth
        let level = min(1, max(0, level))
        for side in [-1.0, 1] {
            let centre = InkGeometry.eyeCentre
            let rect = CGRect(x: side * centre.x + offset - radius, y: centre.y - height / 2,
                              width: 2 * radius, height: height)
            var inside = context
            inside.clip(to: Path(roundedRect: rect, cornerRadius: radius))
            inside.fill(
                Path(CGRect(x: rect.minX, y: rect.maxY - height * level, width: rect.width, height: height * level)),
                with: .color(ink)
            )
            let outline = Path(roundedRect: rect.insetBy(dx: Self.outlineWidth / 2, dy: Self.outlineWidth / 2),
                               cornerRadius: radius - Self.outlineWidth / 2)
            context.stroke(outline, with: .color(ink.opacity(Self.outlineOpacity)), lineWidth: Self.outlineWidth)
        }
    }
}

/// The ink's level easing from where it was to the new figure.
private struct FillTween {
    var from = 0.0
    var to = 0.0
    var start = Date.distantPast

    func level(at date: Date) -> Double {
        let t = min(1, max(0, date.timeIntervalSince(start) / ModelPreparationFace.fillDuration))
        // Ease out: the ink rises quickly, then settles.
        return from + (to - from) * (1 - pow(1 - t, 3))
    }

    func retargeted(to target: Double, at date: Date) -> FillTween {
        FillTween(from: level(at: date), to: target, start: date)
    }
}
