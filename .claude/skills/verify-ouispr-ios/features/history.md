# History of transcriptions

- **ID:** `history`
- **Tier:** Free, search past 7 days Pro (Pro offer, 25 Nov 2026)
- **Targets:** OuisprApp + OuisprCore
- **Screens:** `app.history`, `app.pro.history`, `app.history.detail` (not captured) — see [screens.md](screens.md)

## Sub-features

- `history.list`: The last 200 dictations, kept on the phone only, shown as glass cards (a title of up to three words) drifting in rows, one period at a time: Aujourd'hui / Hier / Cette semaine / Plus ancien (`history.period.<today|yesterday|week|older>`). A finger holds a row, drags it, flicks it; the drift resumes 1.5 s later. Reduce Motion and VoiceOver still the rows. A tap opens the card in place (full text, copy, share, « Ouvrir » for a voice note's detail).
- `history.recent`: Home shows the last 5 as two rows (3 + 2, opposite directions) under « Récentes », with « Tout voir » (`home.history`) to the sheet.
- `history.search`: The magnifier beside the period bar (`history.search`) turns the bar into a search field; a non-empty query shows the matching list. Free: the last 7 days, then a row « N dictées plus anciennes correspondent » that opens the Pro window on its history. Pro: everything. An empty query lists the whole history for everyone.
- `history.delete`: Delete one entry (swipe or context menu).
- `history.detail`: An entry's detail: copy, share, add a word to the vocabulary.
- `history.clear`: « Effacer l'historique » in Réglages → Transcription.
- `history.toggle`: « Historique » on/off switch.
- `history.home-entry`: « Tout voir » above Home's recent cards (`home.history`), or a swipe up.

## How to get to it (user POV)

1. Open Ouispr → Accueil.
2. Tap « Tout voir » (or swipe up) to see past dictations; pick a period; tap a card to open it.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-ouispr-ios/scripts/drive.sh set-default ouispr.debugProEntitlementForced -bool YES
.claude/skills/verify-ouispr-ios/scripts/drive.sh tab Accueil
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-id home.history
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-id history.period.older
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label Fermer
```

## Gotchas

- **Seeding without a dictation:** write `transcription_history.json` into the App Group container (`xcrun simctl get_app_container <udid> com.pivi.dictus group.solutions.pivi.dictus`), an array of `TranscriptionRecord`, then relaunch: Home's recent rows and the sheet's cards show it. Without a model Home hides its mic but still shows the cards.
- The rows move: a screenshot catches them anywhere in their drift. Turn on Reduce Motion for a still capture.
- `Historique` also labels the Pro hub row and the switch on its page: use the Home tab first so the right one is on top.
