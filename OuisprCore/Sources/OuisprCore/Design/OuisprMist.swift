#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/OuisprMist.swift
// The living mist behind Home, the history and the recording screen.
import SwiftUI

/// The background mist: the screen's colour with three soft clouds of the brand's blues
/// (Mist #DBEAFE, Sky #93C5FD, the accent highlight #6BA3FF) drifting over it, slowly
/// enough that it reads as light moving, not as an animation.
///
/// Asked for on 25 Nov 2026 (« brume vivante en fond, légère, sans coût excessif »;
/// the validated sheet: not dimmed under the cards).
///
/// WHY three radial gradients in a `Canvas` and no blur: a gradient that fades to clear
/// is already soft-edged, so there is no offscreen blur pass to pay for; the canvas fills
/// three shapes per frame. The clouds move at most a few points a second, so 20 frames a
/// second is indistinguishable from 120 and costs a sixth. Paused while hidden or in the
/// background; under Reduce Motion it is drawn once, still.
public struct OuisprMist: View {
    /// Whether something covers the screen: the mist then draws no frames.
    public var isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    public init(isPaused: Bool = false) {
        self.isPaused = isPaused
    }

    public var body: some View {
        let still = isPaused || reduceMotion || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still)) { timeline in
            // Under Reduce Motion, one fixed moment: the composition, without the motion.
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for cloud in Self.clouds {
                    cloud.draw(in: &context, size: size, time: time, dark: colorScheme == .dark)
                }
            }
        }
        .background(Color.ouisprBackground)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One cloud: a colour, its strength in light and dark, its size against the screen's
    /// width, and the slow loop its centre follows (a Lissajous figure, periods prime to
    /// each other so the three never fall back into the same arrangement).
    struct Cloud {
        let color: Color
        let lightOpacity: Double
        let darkOpacity: Double
        let radius: Double
        let centre: (x: Double, y: Double)
        let reach: (x: Double, y: Double)
        let periods: (x: Double, y: Double)

        func draw(in context: inout GraphicsContext, size: CGSize, time: Double, dark: Bool) {
            let x = (centre.x + reach.x * sin(2 * .pi * time / periods.x)) * size.width
            let y = (centre.y + reach.y * cos(2 * .pi * time / periods.y)) * size.height
            let r = radius * size.width
            let opacity = dark ? darkOpacity : lightOpacity
            let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.4), color.opacity(0)]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r
                )
            )
        }
    }

    static let clouds: [Cloud] = [
        Cloud(color: Color(hex: 0xDBEAFE), lightOpacity: 0.9, darkOpacity: 0.10, radius: 0.95,
              centre: (0.25, 0.22), reach: (0.12, 0.06), periods: (47, 59)),
        Cloud(color: Color(hex: 0x93C5FD), lightOpacity: 0.35, darkOpacity: 0.12, radius: 0.8,
              centre: (0.8, 0.55), reach: (0.10, 0.08), periods: (61, 43)),
        Cloud(color: Color(hex: 0x6BA3FF), lightOpacity: 0.18, darkOpacity: 0.14, radius: 0.9,
              centre: (0.35, 0.9), reach: (0.14, 0.05), periods: (73, 53))
    ]
}
#endif
