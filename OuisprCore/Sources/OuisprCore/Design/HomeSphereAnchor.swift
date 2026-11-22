// OuisprCore/Sources/OuisprCore/Design/HomeSphereAnchor.swift
// Where Home's sphere is, so the recording screen carries it from there and back.
import Combine
import CoreGraphics
import SwiftUI

/// Where the travelling sphere sits, in the coordinates of the recording screen's slot.
///
/// WHY a pure function: the flight is the one place a wrong sign or a forgotten origin
/// makes the sphere fly in from a corner, and it can be tested without a screen.
public enum SphereFlight {
    /// The sphere's frame, in the slot's own coordinates.
    ///
    /// - Parameters:
    ///   - home: Home's sphere, in window coordinates, or nil when Home has not drawn it.
    ///   - slot: the recording screen's sphere slot, in window coordinates.
    ///   - atHome: true while the sphere has to sit where Home drew it (the first frame of
    ///     the recording screen, and the way back out).
    /// - Returns: the slot's own square, centred, when the sphere is not at home or there
    ///   is no home to go back to.
    public static func frame(home: CGRect?, slot: CGRect, atHome: Bool) -> CGRect {
        if atHome, let home, home.width > 0, home.height > 0 {
            return home.offsetBy(dx: -slot.minX, dy: -slot.minY)
        }
        let side = min(slot.width, slot.height)
        return CGRect(
            x: (slot.width - side) / 2,
            y: (slot.height - side) / 2,
            width: side,
            height: side
        )
    }
}

#if os(iOS)
/// Where Home's sphere is on screen, so the recording screen can carry it (audit of
/// 22 Nov 2026, findings 1 and 2).
///
/// The two spheres already draw one simulation (`sharesMotion`), so at any instant the
/// recording screen's is, to the point, the one Home draws. What it needs on top is
/// Home's spot: it starts its flight there, opaque from the first frame, and lands
/// back there before Home's own is shown again, so the hand-over has nothing to see.
///
/// WHY a measured frame and not `matchedGeometryEffect`: a matched pair is two views,
/// and inserting the recording screen with a transition faded both, which showed two
/// spheres crossing for about 130 ms on the way in (verified on 0457c72). Here only one
/// sphere is ever visible, and only its frame moves.
@MainActor
public final class HomeSphereAnchor: ObservableObject {
    public static let shared = HomeSphereAnchor()

    /// Home's sphere in window coordinates, or nil while Home is not on screen.
    @Published public private(set) var homeFrame: CGRect?

    public init() {}

    public func report(homeFrame frame: CGRect?) {
        // Rounded to half points so sub-point layout noise does not republish.
        let rounded = frame.map { rect in
            CGRect(
                x: (rect.minX * 2).rounded() / 2,
                y: (rect.minY * 2).rounded() / 2,
                width: (rect.width * 2).rounded() / 2,
                height: (rect.height * 2).rounded() / 2
            )
        }
        guard rounded != homeFrame else { return }
        homeFrame = rounded
    }
}

public extension View {
    /// Reports this view's frame as Home's sphere, and clears it when Home goes.
    func reportsHomeSphere() -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            HomeSphereAnchor.shared.report(homeFrame: frame)
        }
        .onDisappear {
            HomeSphereAnchor.shared.report(homeFrame: nil)
        }
    }
}
#endif
