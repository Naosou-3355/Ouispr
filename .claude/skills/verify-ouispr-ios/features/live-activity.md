# Live Activity and Dynamic Island

- **ID:** `live-activity`
- **Tier:** Gratuit (Free)
- **Targets:** OuisprWidgets + OuisprApp
- **Screens:** `widget.live-activity` (not captured) — see [screens.md](screens.md)

## Sub-features

- `live-activity.standby`: An « On » pill in the Dynamic Island while Ouispr is ready.
- `live-activity.states`: Rec, Transcribing, Ready, Error during a dictation.
- `live-activity.stop-standby`: Stop Ouispr between dictations from the island.
- `live-activity.controls`: Dictate and stop buttons in the expanded island.
- `live-activity.toggle`: « Live Activity » switch in Réglages → Clavier.
- `live-activity.inactivity-timeout`: « Délai d’inactivité » picker in Réglages → Clavier (Immédiatement / 1 min / 5 min / 10 min default / 30 min / 1 h / Illimité): how long the engine and the standby pill stay after a dictation (#380).

## How to get to it (user POV)

1. Open Ouispr once: the orange « On » pill appears in the Dynamic Island.
2. Long-press the island to stop Ouispr between dictations.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
axe button home --udid <udid>
.claude/skills/verify-ouispr-ios/scripts/evidence.sh island
```

## Gotchas

- Not reproduced in this skill's runs: with no model installed and the device slimmed, the Home screen showed no island after leaving Ouispr. CLAUDE.md notes (unmeasured) that a Live Activity test needs `simslim on <udid> --except widgets`; `launch.sh` does not pass it.
- A dev install kills running Live Activities; Focus modes drop their alerts. Device only.
