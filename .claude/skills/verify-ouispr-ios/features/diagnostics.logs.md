# Debug logs and diagnostics

- **ID:** `diagnostics.logs`
- **Tier:** Gratuit (Free)
- **Targets:** OuisprApp + OuisprCore
- **Screens:** `app.settings.debug-logs`, `app.settings.diagnostic`, `app.settings.licences`, `app.settings.typing-bench` — see [screens.md](screens.md)

## Sub-features

- `diagnostics.log-view`: « Debug Logs »: the shared app and keyboard log.
- `diagnostics.log-export`: « Exporter les logs » through the share sheet.
- `diagnostics.app-group-check`: « Diagnostic »: checks the storage shared by app and keyboard (App Group).
- `diagnostics.about`: Version, GitHub link, Licences.
- `diagnostics.typing-bench`: « Banc de frappe »: 20 fixed French phrases typed with one keyboard then another (the user labels which: Ouispr or Apple), scored as words per minute, share of right words and character errors (`TypingBenchScoring`). Results stay in the app's own defaults; « Partager les résultats » sends a text summary.

## How to get to it (user POV)

1. Ouispr → Réglages, scroll to À propos.
2. Tap « Exporter les logs » and send the file.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-ouispr-ios/scripts/drive.sh tab Réglages
axe swipe --start-x 201 --start-y 700 --end-x 201 --end-y 150 --duration 0.4 --udid <udid>
axe swipe --start-x 201 --start-y 700 --end-x 201 --end-y 150 --duration 0.4 --udid <udid>
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label Diagnostic
.claude/skills/verify-ouispr-ios/scripts/drive.sh wait-label "Read: OK"
```

The log file itself is readable from the host at `$LOG_FILE` (in `run.env`) and is copied out by `cleanup.sh`.

## Gotchas

- Typing bench: the comparison only means something typed by a finger on the iPhone. In the simulator, axe types a perfect string, so every keyboard scores 100 % and the speed is axe's. The simulator proves the screen, the scoring and the store, not a keyboard's quality.

- The share sheet's destinations are the simulator's, not the phone's; exporting proves the sheet opens, nothing more.
- An unsigned build (CI flags) has no App Group container: no log, Diagnostic fails. `launch.sh` builds signed ad hoc.
