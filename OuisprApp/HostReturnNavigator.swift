// OuisprApp/HostReturnNavigator.swift
// Sends the user back to the app they dictated in, trying each way of `HostReturnPlan` in turn (lot 1.8).
//
// ⚠️ PRIVATE APPLE API. `systemBack` and `openApplication` call undocumented methods
// (`UIApplication._systemNavigationAction`, `LSApplicationWorkspace`). They are resolved
// at run time and guarded, so a missing method is a logged miss, never a crash. Fine for
// a build installed through AltStore or Xcode; App Review rejects private API, so before
// any App Store submission this file's two private steps must go (delete them and
// `HostReturnPlan` falls back to the scheme table and the gesture, as before lot 1.8).
import Combine
import OuisprCore
import UIKit

/// What the « Dictée en cours » screen needs to know about the return: whether it is
/// still being attempted, or whether every way failed and the gesture must be shown.
@MainActor
final class HostReturnProgress: ObservableObject {
    static let shared = HostReturnProgress()

    /// True once every automatic way back has failed: the screen shows the gesture.
    @Published private(set) var needsManualReturn = false

    private init() {}

    func reset() { needsManualReturn = false }
    func giveUp() { needsManualReturn = true }
}

@MainActor
enum HostReturnNavigator {

    /// How long after a step Ouispr may still be in the foreground before the next step is
    /// tried. iOS leaves `.active` within a frame or two of a successful switch; 0.6 s
    /// leaves room for a slow device without making a failed step feel like a wait.
    static let settleDelay: TimeInterval = 0.6

    /// Bumped by every return: a callback from an earlier chain (a dictation started
    /// again within its two seconds) sees it changed and stops.
    private static var generation = 0

    /// How many settle delays a step may wait while Ouispr is `.inactive` (an alert, a
    /// pulled-down Control Center, the system's own switch) before it is judged.
    static let inactiveWaits = 3

    /// Tries each step until Ouispr leaves the foreground, logging every attempt. Called
    /// once the recording is running (`returnToHostApp`'s wait is unchanged).
    static func returnToHost(hostId: String?) {
        generation += 1
        HostReturnProgress.shared.reset()
        let loggedHostId = hostId ?? "unknown"
        // The user may have left by themselves during the wait (the #853 hold lasts up to
        // seconds). Bringing the host back now would override where they went.
        guard UIApplication.shared.applicationState != .background else {
            PersistentLog.log(.hostReturn(hostId: loggedHostId, outcome: "skipped-background"))
            return
        }
        let chain = Chain(generation: generation, hostId: loggedHostId)
        chain.attempt(HostReturnPlan.steps(hostId: hostId)[...])
    }

    /// One return's walk down the plan.
    @MainActor
    private struct Chain {
        let generation: Int
        let hostId: String

        var isCurrent: Bool { generation == HostReturnNavigator.generation }

        func log(_ outcome: String) {
            PersistentLog.log(.hostReturn(hostId: hostId, outcome: outcome))
        }

        func attempt(_ steps: ArraySlice<HostReturnStep>) {
            guard isCurrent, let step = steps.first else { return }
            let rest = steps.dropFirst()
            let name = HostReturnPlan.logName(step)

            switch step {
            case .manual:
                log("manual")
                HostReturnProgress.shared.giveUp()
            case .systemBack:
                trySystemBack(rest: rest, polls: 0)
            case .openApplication(let bundleId):
                guard HostReturnNavigator.openApplication(bundleId: bundleId) else {
                    log("openApplication-refused")
                    attempt(rest)
                    return
                }
                confirm(name, rest: rest, waits: 0)
            case .urlScheme(let url):
                UIApplication.shared.open(url, options: [:]) { opened in
                    guard opened else {
                        log("open-failed")
                        attempt(rest)
                        return
                    }
                    confirm(name, rest: rest, waits: 0)
                }
            }
        }

        func trySystemBack(rest: ArraySlice<HostReturnStep>, polls: Int) {
            guard isCurrent else { return }
            guard let missing = HostReturnNavigator.sendSystemBack() else {
                confirm("systemBack polls=\(polls)", rest: rest, waits: 0)
                return
            }
            guard missing == "noLink", polls < HostReturnNavigator.linkPolls else {
                log("systemBack-unavailable reason=\(missing) polls=\(polls)")
                attempt(rest)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                trySystemBack(rest: rest, polls: polls + 1)
            }
        }

        /// A step was sent: it worked once Ouispr is in the background. `.inactive` is not
        /// an answer yet (an alert or the system's switch), so the check waits for it.
        func confirm(_ name: String, rest: ArraySlice<HostReturnStep>, waits: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + HostReturnNavigator.settleDelay) {
                guard isCurrent else { return }
                switch UIApplication.shared.applicationState {
                case .background:
                    log("returned via=\(name)")
                case .inactive where waits < HostReturnNavigator.inactiveWaits:
                    confirm(name, rest: rest, waits: waits + 1)
                default:
                    log("\(name)-stayed")
                    attempt(rest)
                }
            }
        }
    }

    /// iOS may attach the « ◀ App » link a moment after Ouispr became active, so a missing
    /// link is asked for again every 0.1 s, up to `linkPolls` times, before moving on.
    static let linkPolls = 1

    // MARK: - Private API, guarded

    /// Taps iOS's « ◀ App » back link: `UIApplication._systemNavigationAction` is the
    /// object behind it, and destination 0 is « back ». Returns nil once sent, or what was
    /// missing: `noLink` when iOS shows no link (Ouispr was not opened from another app),
    /// the other reasons when the private methods are gone.
    private static func sendSystemBack() -> String? {
        guard let action = systemNavigationAction() else { return "noLink" }

        let destinationsSelector = NSSelectorFromString("destinations")
        if action.responds(to: destinationsSelector),
           let destinations = action.perform(destinationsSelector)?.takeUnretainedValue() as? [NSNumber],
           !destinations.contains(0) {
            return "noBackDestination"
        }

        let sendSelector = NSSelectorFromString("sendResponseForDestination:")
        guard action.responds(to: sendSelector), let method = action.method(for: sendSelector) else { return "noSend" }
        typealias SendResponse = @convention(c) (AnyObject, Selector, Int) -> Void
        let send = unsafeBitCast(method, to: SendResponse.self)
        send(action, sendSelector, 0)
        return nil
    }

    /// The object behind the « ◀ App » link, from the application. Only the underscored
    /// getter, whose return is an object or nil: asking other owners or names risks a
    /// selector that returns a non-object, which `perform` would mistake for one.
    private static func systemNavigationAction() -> NSObject? {
        let selector = NSSelectorFromString("_systemNavigationAction")
        guard UIApplication.shared.responds(to: selector) else { return nil }
        return UIApplication.shared.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    /// Brings `bundleId` to the front as the app switcher does, resuming it where it was.
    /// Returns false when the workspace is unavailable or refuses.
    private static func openApplication(bundleId: String) -> Bool {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return false }
        let defaultSelector = NSSelectorFromString("defaultWorkspace")
        guard workspaceClass.responds(to: defaultSelector),
              let workspace = workspaceClass.perform(defaultSelector)?.takeUnretainedValue() as? NSObject
        else { return false }

        let openSelector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: openSelector), let method = workspace.method(for: openSelector) else { return false }
        typealias OpenApplication = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(method, to: OpenApplication.self)
        return open(workspace, openSelector, bundleId as NSString)
    }
}
