# History of transcriptions

- **ID:** `history`
- **Tier:** Free, search past 7 days Pro (Pro offer, 25 Nov 2026)
- **Targets:** OuisprApp + OuisprCore
- **Screens:** `app.history`, `app.pro.history`, `app.history.detail` (not captured) — see [screens.md](screens.md)

## Sub-features

- `history.list`: The last 200 dictations, kept on the phone only.
- `history.search`: « Rechercher dans les transcriptions ». Free: the last 7 days, then a row « N dictées plus anciennes correspondent » that opens the Pro window on its history. Pro: everything. An empty query lists the whole history for everyone.
- `history.delete`: Delete one entry (swipe or context menu).
- `history.detail`: An entry's detail: copy, share, add a word to the vocabulary.
- `history.clear`: « Effacer l'historique » in Réglages → Transcription.
- `history.toggle`: « Historique » on/off switch.
- `history.home-entry`: « Historique » button on Home (swipe up).

## How to get to it (user POV)

1. Open Ouispr → Accueil.
2. Tap « Historique » (or swipe up) to see past dictations; tap one for details.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-ouispr-ios/scripts/drive.sh set-default ouispr.debugProEntitlementForced -bool YES
.claude/skills/verify-ouispr-ios/scripts/drive.sh tab Accueil
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label Historique
.claude/skills/verify-ouispr-ios/scripts/drive.sh wait-label "Aucune transcription pour l’instant"
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label Fermer
```

## Gotchas

- **Not drivable in the simulator without a real dictation:** a non-empty list, the detail screen, search results. Entries come only from a transcription (model + recording). The empty state is what an agent can show.
- `Historique` also labels the Pro hub row and the switch on its page: use the Home tab first so the right one is on top.
