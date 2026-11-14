// DictusCore/Sources/DictusCore/AppGroup.swift
import Foundation
#if os(macOS)
import Security
#endif

public enum AppGroup {
    /// The App Group declared in the four `.entitlements` files.
    public static let baseIdentifier = "group.solutions.pivi.dictus"

    /// The App Group this process is actually in.
    ///
    /// WHY not always `baseIdentifier`: a free Apple ID cannot register someone
    /// else's group, so AltStore re-signs a sideloaded app with
    /// `<group>.<TEAMID>` and writes the groups it granted into each bundle's
    /// Info.plist under `ALTAppGroups`. Keeping the base name there would give the
    /// app and the keyboard two private, unrelated stores: the keyboard would
    /// never see the onboarding, the model or the transcriptions the app writes.
    public static let identifier = resolve(
        base: baseIdentifier,
        altAppGroups: Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]
    )

    /// Pick the AltStore-granted variant of `base`, or `base` itself.
    ///
    /// The shortest match wins, as in AltStore's own remapping: the team-suffixed
    /// group is `base` plus one component, anything longer is another group.
    static func resolve(base: String, altAppGroups: [String]?) -> String {
        let candidates = (altAppGroups ?? []).filter { $0 == base || $0.hasPrefix(base + ".") }
        return candidates.min(by: { $0.count < $1.count }) ?? base
    }

    /// Shared UserDefaults for cross-process data.
    /// Force-unwrap justified: if this fails, the App Group entitlement
    /// is misconfigured and the app cannot function.
    public static var defaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            fatalError("App Group '\(identifier)' not configured. Check entitlements.")
        }
        return defaults
    }

    /// Shared file container URL for larger data (audio, models metadata).
    ///
    /// WHY `nil` on a Mac without the entitlement: iOS already answers `nil` to a
    /// process that is not in the group, but macOS hands back the path anyway, to
    /// a folder it then guards for the app that owns it. The only Mac processes
    /// running this code are the `swift test` host and `polish-harness`, and their
    /// every `open()` in there is held on an authorization prompt that, under a
    /// host with no Full Disk Access, never resolves: the test run hangs instead of
    /// failing. Answering `nil` makes them take the path every store already has
    /// for "no container".
    public static var containerURL: URL? {
        #if os(macOS)
        guard isEntitledToGroup else { return nil }
        #endif
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }

    #if os(macOS)
    /// Whether this process's signature lists the Dictus App Group.
    private static let isEntitledToGroup: Bool = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.security.application-groups" as CFString, nil
              ),
              let groups = value as? [String] else { return false }
        return groups.contains(identifier)
    }()
    #endif
}
