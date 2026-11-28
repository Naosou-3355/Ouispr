# Return to the app you were typing in

- **ID:** `dictation.return-to-app`
- **Tier:** Gratuit (Free)
- **Targets:** OuisprApp + OuisprKeyboard
- **Screens:** `app.listening-handoff` (« J'écoute », lot 1.8) — see [screens.md](screens.md)

## Sub-features

- `return.swipe-back`: The screen a keyboard dictation shows while Ouispr is in front (lot 1.8): the app's backdrop, the ink character listening, « J'écoute ». After 1 s the sentence on why Ouispr had to open fades in; the gesture line (« Glissez vers la droite en bas de l'écran pour revenir ») appears only when every automatic way back failed (`hostReturn … outcome=manual`).
- `return.auto-return`: Ouispr returns to the host by itself, for every host (lot 1.8, `HostReturnPlan`): iOS's « ◀ App » link (private `UIApplication._systemNavigationAction`), then the host's bundle (private `LSApplicationWorkspace openApplicationWithBundleID:`), then the scheme table, then the gesture. Each step is logged (`systemBack-unavailable reason=…`, `returned via=openApplication`, `manual`). Private API: fine for AltStore/Xcode installs, to remove before any App Store submission (`OuisprApp/HostReturnNavigator.swift`).
  On an ordinary cold start it opens the host app once recording has started, or at 250 ms at the latest. When the cold start's audio session is recovering (first activation refused, typically `'msrv'` after an audio server reset, #853), it holds the foreground instead (`hostReturn … holding reason=audioSessionRecovering`) and opens on recording (`via=recording`), on a failure (`via=failed`) or at 5 s (`via=holdCeiling`). Meanwhile the overlay title reads « Préparation du micro… » instead of « Dictée en cours ».

## How to get to it (user POV)

1. With Ouispr closed, tap the mic in the Ouispr keyboard.
2. Ouispr opens; swipe back (or wait for auto-return) to the app you were typing in.

## Driving it with axe + Argent

The cold start is reachable: run the `dictation.keyboard` recipe and capture the screen after `kbd mic` (`evidence.sh after-mic`). Without a model the app answers with the failure before any overlay, so only the hand-off half is shown.

```bash
.claude/skills/verify-ouispr-ios/scripts/drive.sh wait-log '<APP> coldStartURLReceived isColdStart=true' 20 "$M"
```

## Measured in the simulator (2026-11-28, iOS 26.3, lot 1.8)

Smoke-style chain without a model (`recState=failed` at the 250 ms ceiling, so the return still runs): Safari, Messages and Reminders all came back by themselves, `systemBack-unavailable reason=noLink` then `returned via=openApplication`, about 1.4 s from the mic tap. Messages came back on the same conversation with the keyboard up; Reminders came back on its list (its editing row ends when it resigns active, as with the gesture). The « ◀ App » link is drawn by iOS but `_systemNavigationAction` returns nil in this scene-based app, so `systemBack` has not been seen working. `simctl openurl 'ouispr://dictate?source=keyboard'` (no host, then « Ouvrir ») shows the last fallback with the gesture line. Notes is not installed on the simulator.

## Gotchas

- **Not drivable in the simulator:** whether the return lands in the right host app, and the Spotlight/arbiter cases (#23). Device only; the simulator's host detection is not the phone's.
- **#853 in the simulator, title only:** a Debug build refuses every activation with `'msrv'` for a window after the first one when `debugSimulateAudioServerResetMs` is set in the app's own defaults (`xcrun simctl spawn <udid> defaults write <app data container>/Library/Preferences/com.pivi.ouispr.plist debugSimulateAudioServerResetMs -int 2500`, after `ouispr.modelReady` and `ouispr.hasCompletedOnboarding` via `drive.sh set-default`). The overlay then reads « Préparation du micro… » (captured 2026-10-28, under the microphone permission prompt, which was refused so nothing recorded). Safari has no return scheme, so the held return itself (`holding reason=audioSessionRecovering`) is not reached there.
- **Device only (#853):** the held return and a real audio server reset during a cold start, which nobody can trigger on demand. A reset that lands after OuisprApp has left the foreground must end in « La dictée n’a pas pu démarrer. Touchez à nouveau le micro. » with `engineStartSkipped appState=background` in the log, never a `dictationFailed error=engine.start failed`.
