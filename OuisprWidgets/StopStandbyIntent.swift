// OuisprWidgets/StopStandbyIntent.swift
// LiveActivityIntent to stop the Ouispr standby Dynamic Island.
//
// WHY LiveActivityIntent (not AppIntent):
// Button(intent:) inside a Live Activity requires a LiveActivityIntent.
// Regular AppIntents open the app; LiveActivityIntents execute in-process
// without bringing the app to the foreground.
//
// WHY in both OuisprApp AND OuisprWidgets targets:
// LiveActivityIntent.perform() executes in the HOST APP process, not the
// widget extension. If the type is only compiled into OuisprWidgets,
// iOS can't find it at runtime → silent failure. Both targets must include
// this file so the intent is available wherever iOS needs to run it.
import AppIntents
import ActivityKit
import Foundation
import OuisprCore

struct StopStandbyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Standby"
    static var description = IntentDescription("Turn off Ouispr standby mode")

    func perform() async throws -> some IntentResult {
        // End all Live Activities
        for activity in Activity<OuisprLiveActivityAttributes>.activities {
            await activity.end(
                .init(state: .init(phase: .standby), staleDate: nil),
                dismissalPolicy: .immediate
            )
        }

        // Notify the app process to stop the audio engine (ends the warm standby).
        // WHY NotificationCenter (not calling DictationCoordinator directly):
        // This file is compiled into both OuisprApp and OuisprWidgets targets.
        // DictationCoordinator only exists in OuisprApp — referencing it here
        // would break the OuisprWidgets build. NotificationCenter is available
        // in both, and the notification only reaches the coordinator when running
        // in the app process (which is exactly when we need it).
        await MainActor.run {
            NotificationCenter.default.post(
                name: Notification.Name("OuisprStopStandbyRequested"),
                object: nil
            )
        }

        return .result()
    }
}
