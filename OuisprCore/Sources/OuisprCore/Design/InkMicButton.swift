#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/InkMicButton.swift
// The app's mic: an ink disc carrying the logo's three bars, which melt into a stop square while it listens.
import SwiftUI

/// The round mic of Home and the recording screen, in the ink character's ink.
///
/// Chosen by Alex on the bench of 25 Nov 2026 (« Le logo dans le bouton »). The disc
/// carries the logo's three bars, still: the app's signature, not a second face, so
/// nothing repeats the character drawn larger above it. When a dictation starts the
/// bars squash with the character's eyes, then melt into a stop square for as long as
/// it listens; they stand up again when the dictation ends.
///
/// WHY a view apart from `AnimatedMicButton`: the keyboard's pill keeps that one, with
/// its accent and its glow, and its own reasons (#79, #510). The app's two screens no
/// longer draw a sphere, and this is the button that matches what they draw instead.
///
/// Sources: Apple, WWDC18 « Designing Fluid Interfaces » (one object keeps its identity
/// from state to state: the bars become the square), Material 3 Expressive (buttons
/// that change shape with their state).
public struct InkMicButton: View {
    /// What the dictation behind the button is doing.
    public enum Phase: Equatable {
        /// Ready: the three bars. A tap starts a dictation.
        case resting
        /// Recording: the stop square. A tap ends the dictation.
        case listening
        /// Transcribing or cleaning up: the bars, faded. Not tappable.
        case working
    }

    public let phase: Phase
    /// The armed Smart Mode's mark on the disc's corner, as `AnimatedMicButton` draws it.
    public let badge: SmartModeBadge?
    /// A resting glyph replacing the bars: the armed mode's, on Home (#489).
    public let face: AnimatedMicButton.MicFace?
    public let showsPressFeedback: Bool
    public let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The disc. The slot around it stays `OuisprHalo.size`, the 92 pt the Smart Mode
    /// dial and the mic anchor (#788) are laid out on.
    public static let diameter: CGFloat = 72

    public init(phase: Phase,
                badge: SmartModeBadge? = nil,
                face: AnimatedMicButton.MicFace? = nil,
                showsPressFeedback: Bool = true,
                onTap: @escaping () -> Void) {
        self.phase = phase
        self.badge = badge
        self.face = face
        self.showsPressFeedback = showsPressFeedback
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.ouisprInk)
                    .frame(width: Self.diameter, height: Self.diameter)
                glyph
                    .foregroundStyle(Color.ouisprBackground)
                    .opacity(phase == .working ? 0.4 : 1)
                if let badge {
                    badgeView(badge)
                }
            }
            // The bars' squash and stretch, on the disc as a whole: a press of the
            // character's own anticipation, never a loop.
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: phase) { content, scale in
                content.scaleEffect(reduceMotion ? CGSize(width: 1, height: 1) : scale)
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

    @ViewBuilder
    private var glyph: some View {
        if phase == .resting, let face {
            VStack(spacing: 1) {
                Image(systemName: face.symbol)
                    .font(.system(size: 22, weight: .medium))
                if let caption = face.caption {
                    Text(verbatim: caption)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }
        } else {
            InkMicBars(morph: phase == .listening ? 1 : 0)
                .frame(width: 24, height: 24)
                .animation(reduceMotion ? .easeOut(duration: Motion.quick)
                                        : .spring(response: 0.38, dampingFraction: 0.62),
                           value: phase)
        }
    }

    private func badgeView(_ badge: SmartModeBadge) -> some View {
        Group {
            switch badge {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 12.5, weight: .semibold))
            case .text(let value):
                Text(value)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(Color.ouisprInk)
        .frame(width: 24, height: 24)
        .background(Circle().fill(Color.ouisprBackground))
        .overlay(Circle().stroke(Color.ouisprInk, lineWidth: 1.5))
        .offset(x: 25, y: 25)
    }
}

/// The logo's three bars (heights 18 / 42 / 27, capsule ends) at `morph` 0, the three
/// thirds of a rounded stop square at 1. Animatable, so the bars slide and grow into
/// the square rather than cross-fade.
public struct InkMicBars: Shape {
    public var morph: Double

    public init(morph: Double) {
        self.morph = morph
    }

    public var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        // In a 24 pt box: the logo's bars at 21.3 pt for the tallest, 5 pt wide,
        // 9 pt apart; the square 18 pt, split in three overlapping thirds.
        let unit = min(rect.width, rect.height) / 24
        let heights = [9.1, 21.3, 13.7]
        let restX = [-9.0, 0, 9.0]
        let squareX = [-6.0, 0, 6.0]
        let m = max(0, min(1.2, morph))
        var path = Path()
        for k in 0..<3 {
            let height = (heights[k] + (18 - heights[k]) * m) * unit
            let width = (5 + (6.6 - 5) * m) * unit
            let x = rect.midX + (restX[k] + (squareX[k] - restX[k]) * m) * unit
            let radius = (2.5 + (1.6 - 2.5) * min(1, m)) * unit
            path.addRoundedRect(
                in: CGRect(x: x - width / 2, y: rect.midY - height / 2, width: width, height: height),
                cornerSize: CGSize(width: radius, height: radius)
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
