#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/InkMicButton.swift
// The app's mic: an ink disc carrying the logo's three bars, and a stop square inside it while it listens.
import SwiftUI

/// The round mic of Home and the recording screen, in the ink character's ink.
///
/// Chosen by Alex on the bench of 25 Nov 2026 (« Le logo dans le bouton »). The disc
/// carries the logo's three bars, still: the app's signature, not a second face, so
/// nothing repeats the character drawn larger above it. While it listens the bars give
/// way to a stop square drawn inside the disc; the disc itself never shrinks, so the
/// main action stays the one full shape on screen (Alex, Beta 45 feedback, 25 Nov 2026).
///
/// WHY a view apart from `AnimatedMicButton`: the keyboard's pill keeps that one, with
/// its accent and its glow, and its own reasons (#79, #510). The app's two screens no
/// longer draw a sphere, and this is the button that matches what they draw instead.
///
/// Sources: Apple, WWDC18 « Designing Fluid Interfaces » (one object keeps its identity
/// from state to state), Apple Voice Memos (the stop square inside the record button).
public struct InkMicButton: View {
    /// What the dictation behind the button is doing.
    public enum Phase: Equatable {
        /// Ready: the three bars. A tap starts a dictation.
        case resting
        /// Recording: the stop square, inside the disc. A tap ends the dictation.
        case listening
        /// Transcribing or cleaning up: the bars, faded. Not tappable.
        case working
    }

    public let phase: Phase
    public let showsPressFeedback: Bool
    public let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The disc. The slot around it stays `OuisprHalo.size`, the 92 pt the mic anchor
    /// (#788) is laid out on.
    public static let diameter: CGFloat = 72

    public init(phase: Phase,
                showsPressFeedback: Bool = true,
                onTap: @escaping () -> Void) {
        self.phase = phase
        self.showsPressFeedback = showsPressFeedback
        self.onTap = onTap
    }

    public var body: some View {
        // Read here, not inside the keyframe closure, which runs off the main actor.
        let still = reduceMotion
        return Button(action: onTap) {
            ZStack {
                // Always the full disc: the button stays the screen's main action at
                // every stage, and the stop square is drawn inside it (Alex, retour
                // Beta 45, 25 Nov 2026). No ring around it.
                Circle()
                    .fill(Color.ouisprInk)
                    .frame(width: Self.diameter, height: Self.diameter)
                glyph
                    .foregroundStyle(Color.ouisprBackground)
                    .opacity(phase == .working ? 0.4 : 1)
            }
            // The bars' squash and stretch, on the disc as a whole: a press of the
            // character's own anticipation, never a loop.
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: phase) { content, scale in
                content.scaleEffect(still ? CGSize(width: 1, height: 1) : scale)
            } keyframes: { _ in
                KeyframeTrack(\.height) {
                    CubicKeyframe(phase == .listening ? 0.9 : 1.06, duration: 0.09)
                    SpringKeyframe(1, duration: 0.45, spring: .init(response: 0.32, dampingRatio: 0.5))
                }
                KeyframeTrack(\.width) {
                    CubicKeyframe(phase == .listening ? 1.08 : 0.96, duration: 0.09)
                    SpringKeyframe(1, duration: 0.45, spring: .init(response: 0.32, dampingRatio: 0.5))
                }
            }
            .frame(width: OuisprHalo.size(isPill: false).width, height: OuisprHalo.size(isPill: false).height)
            .contentShape(Circle())
        }
        .buttonStyle(GlassPressStyle(pressedScale: showsPressFeedback ? 0.94 : 1,
                                     pressedOpacity: showsPressFeedback ? 0.85 : 1))
        .disabled(phase == .working)
    }

    /// The bars give way to the stop square, both inside the disc.
    private var glyph: some View {
        let listening = phase == .listening
        return ZStack {
            InkMicBars()
                .frame(width: 24, height: 24)
                .scaleEffect(listening ? 0.6 : 0.85)
                .opacity(listening ? 0 : 1)
            RoundedRectangle(cornerRadius: Self.stopCornerRadius, style: .continuous)
                .frame(width: Self.stopSide, height: Self.stopSide)
                .scaleEffect(listening ? 1 : 0.5)
                .opacity(listening ? 1 : 0)
        }
        .animation(glyphAnimation, value: phase)
    }

    /// The stop square inside the disc: about a third of it, Apple's Voice Memos ratio.
    static let stopSide: CGFloat = 24
    static let stopCornerRadius: CGFloat = 6

    private var glyphAnimation: Animation {
        reduceMotion ? .easeOut(duration: Motion.quick) : .spring(response: 0.32, dampingFraction: 0.72)
    }
}

/// The logo's three bars (heights 18 / 42 / 27, capsule ends), in a 24 pt box.
struct InkMicBars: Shape {
    func path(in rect: CGRect) -> Path {
        // The tallest bar 21.3 pt, 5 pt wide, 9 pt apart.
        let unit = min(rect.width, rect.height) / 24
        let heights = [9.1, 21.3, 13.7]
        let offsets = [-9.0, 0, 9.0]
        var path = Path()
        for k in 0..<3 {
            let height = heights[k] * unit
            let width = 5 * unit
            let x = rect.midX + offsets[k] * unit
            path.addRoundedRect(
                in: CGRect(x: x - width / 2, y: rect.midY - height / 2, width: width, height: height),
                cornerSize: CGSize(width: width / 2, height: width / 2)
            )
        }
        return path
    }
}

#Preview("Ink mic") {
    HStack(spacing: 24) {
        InkMicButton(phase: .resting) {}
        InkMicButton(phase: .listening) {}
        InkMicButton(phase: .working) {}
    }
    .padding()
    .background(Color.ouisprBackground)
}
#endif
