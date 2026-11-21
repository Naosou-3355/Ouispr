// OuisprCore/Sources/OuisprCore/OuisprVariant.swift
// Which Ouispr this process is: the everyday app or the side-by-side trial app.
import Foundation

/// The two builds of Ouispr that can sit on the same iPhone.
///
/// WHY: a redesign has to be tried on a real phone without replacing the app that
/// works. "Ouispr Beta" is the same code installed next to it, and the two must share
/// nothing: not the stored dictations, not the URL that opens the app, not the signals
/// the keyboard sends. Every name that crosses a process boundary is read from here,
/// so the two apps can never answer each other.
///
/// The Beta is temporary. Deleting it means deleting `scripts/apply-beta-variant.py`
/// and its workflow steps; this type can then go back to one case.
public enum OuisprVariant: String, Equatable, Sendable {
    case standard
    case beta

    /// The variant of the running process, app or keyboard.
    ///
    /// WHY the bundle identifier and not a build flag: it is the one value the build,
    /// the signature and iOS all agree on, so it cannot say "beta" while the app is
    /// signed as the everyday one. A keyboard's identifier sits under its app's, so
    /// both processes of one install always resolve to the same variant.
    public static let current = resolve(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// The variant a bundle identifier belongs to. Anything that is not under the
    /// Beta prefix (the test host, a nil identifier) is the standard app.
    static func resolve(bundleIdentifier: String?) -> OuisprVariant {
        guard let bundleIdentifier else { return .standard }
        let betaPrefix = OuisprVariant.beta.bundlePrefix
        if bundleIdentifier == betaPrefix || bundleIdentifier.hasPrefix(betaPrefix + ".") {
            return .beta
        }
        return .standard
    }

    /// The prefix every bundle identifier of this variant starts with. A sideloading
    /// tool appends the team to it (`<prefix>.<TEAM>`, `<prefix>.<TEAM>.keyboard`).
    public var bundlePrefix: String {
        switch self {
        case .standard: return "com.pivi.dictus"
        case .beta: return "com.pivi.ouisprbeta"
        }
    }

    /// The App Group declared in the `.entitlements` files of this variant.
    public var appGroupBase: String {
        switch self {
        case .standard: return "group.solutions.pivi.dictus"
        case .beta: return "group.solutions.pivi.ouisprbeta"
        }
    }

    /// The URL scheme the app registers in `CFBundleURLTypes`.
    public var urlScheme: String {
        switch self {
        case .standard: return "ouispr"
        case .beta: return "ouisprbeta"
        }
    }

    /// The prefix of the Darwin notification names. These names are system-wide, so
    /// two apps sharing them would start and stop each other's recordings.
    public var notificationPrefix: String {
        switch self {
        case .standard: return "com.pivi.ouispr"
        case .beta: return "com.pivi.ouisprbeta"
        }
    }
}
