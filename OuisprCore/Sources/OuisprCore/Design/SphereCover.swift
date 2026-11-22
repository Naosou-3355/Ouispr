// OuisprCore/Sources/OuisprCore/Design/SphereCover.swift
// Whether something is presented over Home's sphere, so it can stop drawing.
import Combine
import SwiftUI

/// Counts the screens presented over Home: sheets, full-screen covers, onboarding.
///
/// WHY: a sheet or a cover hides Home's sphere, but SwiftUI keeps the view below alive,
/// and its timeline kept asking for 30 frames a second under them. Measured on
/// 22 Nov 2026 in the simulator: the same CPU with the Settings sheet open as without,
/// about 25 % of a core, for a sphere nobody could see.
///
/// WHY a count and not a flag: presentations stack (Settings, then its paywall), and the
/// sphere must not wake when the top one goes while another is still up.
@MainActor
public final class SphereCover: ObservableObject {
    public static let shared = SphereCover()

    /// How many presentations are up.
    @Published public private(set) var depth = 0

    public var isCovered: Bool { depth > 0 }

    public init() {}

    public func cover() { depth += 1 }

    public func uncover() { depth = max(0, depth - 1) }
}

#if os(iOS)
public extension View {
    /// Marks this view, the content of a sheet or a cover, as hiding Home's sphere for
    /// as long as it is on screen.
    func coversHomeSphere() -> some View {
        onAppear { SphereCover.shared.cover() }
            .onDisappear { SphereCover.shared.uncover() }
    }
}
#endif
