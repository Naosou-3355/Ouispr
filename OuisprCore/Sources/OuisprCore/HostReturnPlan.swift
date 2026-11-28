// OuisprCore/Sources/OuisprCore/HostReturnPlan.swift
// The order in which OuisprApp tries to send the user back to the app they dictated in (lot 1.8).
import Foundation

/// One way back to the host app, tried in `HostReturnPlan.steps(hostId:)`'s order.
public enum HostReturnStep: Equatable, Sendable {
    /// iOS's own « ◀ App » back link, top left of the status bar: it resumes the app
    /// exactly where it was. Private API, only when iOS shows the link.
    case systemBack
    /// Bring the app back to the front by its bundle identifier, as the app switcher does,
    /// which resumes it where it was. Private API.
    case openApplication(bundleId: String)
    /// The app's URL scheme from `KnownAppSchemes`: public, but some schemes land on the
    /// app's home rather than where the user was, so it comes after the two above.
    case urlScheme(URL)
    /// Nothing worked: the screen shows the swipe-back gesture.
    case manual
}

/// Why the return used to fail, and the order that makes it almost always work.
///
/// Before lot 1.8 the only way back was a URL scheme from `KnownAppSchemes`. Any host
/// without one stayed on the « Dictée en cours » screen and the user had to swipe back by
/// hand: Safari and Claude (deliberately, their schemes open a blank tab or a new chat),
/// Spotlight, every app nobody had mapped, and any dictation whose host could not be
/// identified. Alex's iPhone capture of 28 Nov 2026 shows « ◀ Claude »: the host was
/// Claude, which has no scheme, so nothing happened.
///
/// The fix tries iOS's own back link first, the one the user would otherwise tap: it
/// exists whenever iOS opened Ouispr from another app and resumes that app untouched,
/// with no table to maintain. Then the bundle identifier, then the scheme, then the
/// gesture. Each step is only tried if the previous one left Ouispr in the foreground.
///
/// Pure, so the order is tested in OuisprCore; the private calls themselves live in one
/// file of OuisprApp (`HostReturnNavigator`) so they can be removed in one place.
public enum HostReturnPlan {

    /// Hosts that are not apps one can bring back by bundle identifier: view services
    /// shown inside another app, and the home screen. The system back link still works
    /// for them, which is why they are excluded from that one step only.
    static let notLaunchableHosts: Set<String> = [
        "com.apple.SafariViewService",
        "com.apple.springboard",
        "com.apple.mobilesms.compose",
        "com.apple.ShortcutsUI",
        "com.apple.AppleMediaServicesUI.ComposeReviewExtension"
    ]

    /// Ouispr's own bundles, either variant, with or without the team suffix a
    /// sideloading tool appends: the keyboard was used inside Ouispr, there is nowhere to go.
    static func isOuispr(_ hostId: String) -> Bool {
        [OuisprVariant.standard, .beta].contains { variant in
            hostId == variant.bundlePrefix || hostId.hasPrefix(variant.bundlePrefix + ".")
        }
    }

    /// The steps to try, in order. Always ends with `.manual`.
    public static func steps(hostId: String?) -> [HostReturnStep] {
        if let hostId, isOuispr(hostId) { return [.manual] }
        var steps: [HostReturnStep] = [.systemBack]
        if let hostId, !hostId.isEmpty {
            if !notLaunchableHosts.contains(hostId) {
                steps.append(.openApplication(bundleId: hostId))
            }
            if let url = KnownAppSchemes.returnURL(forHostId: hostId) {
                steps.append(.urlScheme(url))
            }
        }
        steps.append(.manual)
        return steps
    }

    /// The step's name in the `hostReturn` log lines.
    public static func logName(_ step: HostReturnStep) -> String {
        switch step {
        case .systemBack: return "systemBack"
        case .openApplication: return "openApplication"
        case .urlScheme: return "urlScheme"
        case .manual: return "manual"
        }
    }
}
