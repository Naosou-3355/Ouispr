# History of transcriptions

- **ID:** `history`
- **Tier:** Free, search past 7 days Pro (Pro offer, 25 Nov 2026)
- **Targets:** OuisprApp + OuisprCore
- **Screens:** `app.history`, `app.history.search`, `app.home.card-preview` (not captured), `app.pro.history`, `app.history.detail` (not captured) — see [screens.md](screens.md)

## Sub-features

- `history.list`: The last 200 dictations, kept on the phone only, shown as glass cards drifting in rows, one period at a time: Aujourd'hui / Hier / Cette semaine / Plus ancien (`history.period.<today|yesterday|week|older>`), only the periods that hold a dictation. The cards show a sharp excerpt of up to eight words on two lines (Home's, a title of up to three words), coming in from a faint blur all at once; a dictation with no words has no card, and the same words dictated twice in a row make one card. Two cards a row, up to four rows. A row too short to loop pans slowly from side to side instead and cannot be dragged; the cards fade over the screen's last 20 pt. A long press shows the native preview with the whole text. A finger holds a row, drags it, flicks it; the drift resumes 1.5 s later. Reduce Motion and VoiceOver still the rows. A tap opens the card in place (full text, copy, share, « Ouvrir » for a voice note's detail).
- `history.recent`: Home shows the last 5 as two rows (3 + 2, opposite directions) under « Récentes », with « Tout voir » (`home.history`) to the sheet.
- `history.search`: The magnifier beside the period bar (`history.search`, crossfading to ✕) turns the bar into a search field. While searching the list always shows: the latest dictations under an empty field, the matches once something is typed, newest first in a stable order; « Aucun résultat pour « … » » only when nothing matches. Free: the last 7 days, then a row « N dictées plus anciennes correspondent » that opens the Pro window on its history. Pro: everything. An empty query lists the whole history for everyone.
- `history.delete`: Delete one entry (swipe or context menu).
- `history.detail`: An entry's detail: copy, share, add a word to the vocabulary.
- `history.clear`: « Effacer l'historique » in Réglages → Transcription, under its own « Dictées enregistrées » count row.
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
- At rest a looping row is moved by a repeating animation, not redrawn by the app; a touch hands it to a timeline at the display's rate until the drift is back at full speed (about 2 s). The drifting cards are drawn in pre-rendered glass (one stretchable image, `FauxCardGlass`), not live Liquid Glass; the internal switch `-OuisprLiveGlass YES` (launch argument) draws them in live glass, for comparisons only. Under the finger the strip of cards compares equal from frame to frame, so only its offset is redrawn.
- `Historique` also labels the Pro hub row and the switch on its page: use the Home tab first so the right one is on top.
