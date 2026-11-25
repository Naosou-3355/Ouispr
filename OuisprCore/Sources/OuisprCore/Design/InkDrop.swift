#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/InkDrop.swift
// A small ink drop that leaves the mic button on a neck, the neck snapping as it goes.
import SwiftUI

/// One of the recording screen's secondary controls (cancel, copy, share), drawn as a
/// drop of the mic's ink that detaches from it.
///
/// Chosen by Alex on the bench of 25 Nov 2026 (« Goutte », « Gouttes »). The drop
/// leaves along `direction` on a neck that thins and snaps, overshoots on its spring
/// and settles; going back, it rises into the mic and the neck forms again. Under
/// Reduce Motion it fades in place, with no neck (WWDC25 « Meet Liquid Glass »: Reduce
/// Motion turns elastic behaviour off).
///
/// WHY drawn under the mic rather than as a control of its own: the neck's root has to
/// disappear into the disc. This view only draws; the tap target is the `InkDropButton`
/// laid over the drop's resting place.
///
/// Sources: Apple, « Applying Liquid Glass to custom views » (shapes that blend and
/// morph apart during a transition), the same idea in ink; the neck is Hiroyuki Sato's
/// metaball construction.
struct InkDropShape: Shape {
    /// 0 inside the mic, 1 at rest. A spring takes it past 1 and back.
    var progress: Double
    let direction: CGVector
    let distance: CGFloat
    let parentRadius: CGFloat
    let dropRadius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Where the drop's centre is at `progress`, from the mic's centre.
    static func offset(_ progress: Double, direction: CGVector, distance: CGFloat) -> CGPoint {
        CGPoint(x: direction.dx * distance * progress, y: direction.dy * distance * progress)
    }

    /// The drop's radius: small as it leaves, full well before it is out.
    func radius(at progress: Double) -> CGFloat {
        let grown = min(1, max(0, progress * 1.5))
        return dropRadius * (0.45 + 0.55 * grown)
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard progress > 0.02 else { return Path() }
        let shift = Self.offset(progress, direction: direction, distance: distance)
        let drop = CGPoint(x: centre.x + shift.x, y: centre.y + shift.y)
        let r = radius(at: progress)
        var path = Path(ellipseIn: CGRect(x: drop.x - r, y: drop.y - r, width: 2 * r, height: 2 * r))
        // The neck holds until the drop is a little further than its own radius from
        // the mic's edge, then snaps.
        if let neck = Self.neck(from: centre, radius: parentRadius, to: drop, radius: r,
                                breakingAt: parentRadius + r * 1.3) {
            path.addPath(neck)
        }
        return path
    }

    /// The bridge between two circles, or nil once it has broken (Hiroyuki Sato's
    /// metaball construction). It pinches as it stretches, so the snap is announced.
    static func neck(from c1: CGPoint, radius r1: CGFloat, to c2: CGPoint, radius r2: CGFloat,
                     breakingAt maxDistance: CGFloat, spread v: CGFloat = 0.5, handle: CGFloat = 2.4) -> Path? {
        let d = hypot(c2.x - c1.x, c2.y - c1.y)
        guard d <= maxDistance, d > abs(r1 - r2) + 0.5 else { return nil }
        let u1 = d < r1 + r2 ? acos((r1 * r1 + d * d - r2 * r2) / (2 * r1 * d)) : 0
        let u2 = d < r1 + r2 ? acos((r2 * r2 + d * d - r1 * r1) / (2 * r2 * d)) : 0
        let between = atan2(c2.y - c1.y, c2.x - c1.x)
        let maxSpread = acos(min(1, max(0, (r1 - r2) / d)))
        let a1 = between + u1 + (maxSpread - u1) * v
        let a2 = between - u1 - (maxSpread - u1) * v
        let a3 = between + .pi - u2 - (.pi - u2 - maxSpread) * v
        let a4 = between - .pi + u2 + (.pi - u2 - maxSpread) * v
        func point(_ c: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        let p1 = point(c1, r1, a1), p2 = point(c1, r1, a2), p3 = point(c2, r2, a3), p4 = point(c2, r2, a4)
        let total = r1 + r2
        let d2 = min(v * handle, hypot(p1.x - p3.x, p1.y - p3.y) / total) * min(1, d * 2 / total)
        let stretch = (d - (r1 - r2)) / (maxDistance - (r1 - r2))
        let t = min(1, max(0, (stretch - 0.6) / 0.4))
        let pinch = 1 - 0.55 * t * t * (3 - 2 * t)
        let mid = CGPoint(x: (c1.x + c2.x) / 2, y: (c1.y + c2.y) / 2)
        func handlePoint(_ p: CGPoint, _ r: CGFloat, _ a: CGFloat) -> CGPoint {
            let h = point(p, r, a)
            return CGPoint(x: mid.x + (h.x - mid.x) * pinch, y: mid.y + (h.y - mid.y) * pinch)
        }
        var path = Path()
        path.move(to: p1)
        path.addCurve(to: p3, control1: handlePoint(p1, r1 * d2, a1 - .pi / 2), control2: handlePoint(p3, r2 * d2, a3 + .pi / 2))
        path.addLine(to: p4)
        path.addCurve(to: p2, control1: handlePoint(p4, r2 * d2, a4 - .pi / 2), control2: handlePoint(p2, r1 * d2, a2 + .pi / 2))
        path.closeSubpath()
        return path
    }
}

/// The drop's glyph, carried with it: hidden while it leaves, shown once it is out.
private struct InkDropGlyph: View, Animatable {
    var progress: Double
    let symbol: String
    let direction: CGVector
    let distance: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let shift = InkDropShape.offset(progress, direction: direction, distance: distance)
        let t = min(1, max(0, (progress - 0.55) / 0.35))
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.ouisprBackground)
            .offset(x: shift.x, y: shift.y)
            .opacity(t * t * (3 - 2 * t))
    }
}

/// An ink drop with its glyph, centred on the mic it leaves. Draws only: hit testing
/// is off, the tap goes to the button laid over the drop's resting place.
public struct InkDrop: View {
    public let isOut: Bool
    public let symbol: String
    public let direction: CGVector
    public let distance: CGFloat
    /// Delay before leaving, so the drop follows the mic's own press.
    public let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The drop's diameter at rest. The button over it is 44 pt, Apple's minimum.
    public static let diameter: CGFloat = 38

    public init(isOut: Bool, symbol: String, direction: CGVector, distance: CGFloat, delay: Double = 0) {
        self.isOut = isOut
        self.symbol = symbol
        self.direction = direction
        self.distance = distance
        self.delay = delay
    }

    public var body: some View {
        let progress: Double = isOut ? 1 : 0
        ZStack {
            if reduceMotion {
                // Fades in place: no neck, no travel.
                Circle()
                    .fill(Color.ouisprInk)
                    .frame(width: Self.diameter, height: Self.diameter)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ouisprBackground)
                    }
                    .offset(x: direction.dx * distance, y: direction.dy * distance)
                    .opacity(progress)
            } else {
                InkDropShape(progress: progress, direction: direction, distance: distance,
                             parentRadius: InkMicButton.diameter / 2, dropRadius: Self.diameter / 2)
                    .fill(Color.ouisprInk)
                InkDropGlyph(progress: progress, symbol: symbol, direction: direction, distance: distance)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: Motion.standard)
                                : .spring(response: 0.95, dampingFraction: 0.52).delay(isOut ? delay : 0),
                   value: isOut)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
