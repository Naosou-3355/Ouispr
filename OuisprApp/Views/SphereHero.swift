// OuisprApp/Views/SphereHero.swift
// One sphere on screen: Home's sphere glides into the recording screen and back.
import SwiftUI

/// The namespace Home's sphere and the recording screen's sphere share, and which of
/// the two the others follow.
///
/// WHY a matched geometry effect: the audit of 22 Nov 2026 saw two spheres at once
/// when a dictation opened or closed, the recording screen arriving in one frame on
/// top of Home. Matched geometry makes SwiftUI animate the frame of the sphere from
/// where it was to where it is going, so the eye follows one object.
///
/// WHY in the environment: Home and the recording screen are far apart in the view
/// tree (one under the navigation stack, the other over it). `MainTabView` owns the
/// `@Namespace` and hands it down; where nobody did, as in onboarding, the effect is
/// simply not applied.
struct SphereHero {
    let namespace: Namespace.ID
    /// True while the recording screen is up: its sphere is the one the other follows.
    let recordingShown: Bool

    static let id = "ouispr.sphere"
}

private struct SphereHeroKey: EnvironmentKey {
    static let defaultValue: SphereHero? = nil
}

extension EnvironmentValues {
    var sphereHero: SphereHero? {
        get { self[SphereHeroKey.self] }
        set { self[SphereHeroKey.self] = newValue }
    }
}

/// Where the sphere sits: on Home, or on the recording screen.
enum SphereHeroPlace {
    case home
    case recording
}

private struct SphereHeroModifier: ViewModifier {
    let place: SphereHeroPlace
    @Environment(\.sphereHero) private var hero

    func body(content: Content) -> some View {
        if let hero {
            // Exactly one source at a time: the recording screen's while it is up,
            // Home's otherwise. During the closing fade the recording sphere follows
            // Home's frame, which is the glide back.
            let isSource = (place == .recording) == hero.recordingShown
            content.matchedGeometryEffect(id: SphereHero.id, in: hero.namespace, isSource: isSource)
        } else {
            content
        }
    }
}

extension View {
    /// Joins the sphere that glides between Home and the recording screen.
    func sphereHero(_ place: SphereHeroPlace) -> some View {
        modifier(SphereHeroModifier(place: place))
    }
}
