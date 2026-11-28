#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/OuisprBackdrop.swift
// The still background behind Home, the history and the recording screen.
import SwiftUI

/// The screen's colour under a faint veil of the accent blue, strongest at the top and
/// gone two thirds of the way down. It never moves.
///
/// Chosen on the « Banc Ouispr épuré » (Alex, 27 Nov 2026, « Voile léger »): it replaces
/// the drifting mist, which was one more thing moving behind a screen meant to be quiet.
///
/// WHY a `LinearGradient` and not a `Canvas`: a still gradient is drawn once and kept
/// by the render server; nothing is redrawn per frame, so it costs nothing while Home is
/// on screen.
public struct OuisprBackdrop: View {
    /// The veil's strength at the top of the screen: 6 % of the accent.
    static let veilOpacity = 0.06

    public init() {}

    public var body: some View {
        let veil = Color(hex: 0x3D7EFF)
        LinearGradient(
            stops: [
                .init(color: veil.opacity(Self.veilOpacity), location: 0),
                .init(color: veil.opacity(Self.veilOpacity * 0.45), location: 0.38),
                .init(color: veil.opacity(0), location: 0.7)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .background(Color.ouisprBackground)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
