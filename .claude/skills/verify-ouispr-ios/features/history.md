# History of transcriptions

- **ID:** `history`
- **Tier:** Free, search past 7 days Pro (Pro offer, 25 Nov 2026)
- **Targets:** OuisprApp + OuisprCore
- **Screens:** `app.history`, `app.history.search`, `app.home.card-preview` (retired 27 Nov 2026), `app.pro.history`, `app.history.detail` (not captured) — see [screens.md](screens.md)

## Sub-features

- `history.list`: The last 200 dictations, kept on the phone only, as a native inset-grouped `List` under a large title « Historique » (« Banc Ouispr épuré », 27 Nov 2026): sections Aujourd'hui / Hier / Semaine / Plus ancien, only those that hold a dictation. Each row is `DictationRow`: the text on up to two lines, the time (today) or the date on the right of the first line, 72 pt minimum at the default text size, on the plain surface (no glass). A dictation with no words has no row, and the same words dictated twice in a row make one row. Nothing moves. A tap pushes the entry's detail (a voice note opens its result screen).
- `history.recent`: Home shows the last 3 (same rules: words only, no consecutive repeats) as flat `DictationRow`s on one plain surface under « Récentes », with « Tout voir » (`home.history`, 44 pt) to the sheet. A row opens the dictation's detail in a sheet (`home.recent.<uuid>`). A new dictation is simply the new first row once the recording screen leaves; no flight.
- `history.search`: The system's `.searchable` field « Rechercher dans les transcriptions »: at the bottom of the sheet on iOS 26 (thumb reach), under the title on iOS 17–18. Only shown while there are records and History is on. Matches newest first in a stable order, still sectioned by period; « Aucun résultat pour « … » » only when nothing matches. Free: the last 7 days, then a row « N dictées plus anciennes correspondent » that opens the Pro window on its history. Pro: everything. An empty query lists the whole history for everyone.
- `history.delete`: Delete one entry (swipe or context menu).
- `history.detail`: An entry's detail: copy, share, add a word to the vocabulary.
- `history.clear`: « Effacer l'historique » in Réglages → Transcription, under its own « Dictées enregistrées » count row.
- `history.toggle`: « Historique » on/off switch.
- `history.home-entry`: « Tout voir » above Home's recent rows (`home.history`), or a swipe up.

## How to get to it (user POV)

1. Open Ouispr → Accueil.
2. Tap « Tout voir » (or swipe up) to see past dictations, by period; tap a row to open it; the search field is at the bottom.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-ouispr-ios/scripts/drive.sh set-default ouispr.debugProEntitlementForced -bool YES
.claude/skills/verify-ouispr-ios/scripts/drive.sh tab Accueil
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-id home.history
.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label Fermer
```

## Gotchas

- **Seeding without a dictation:** write `transcription_history.json` into the App Group container (`xcrun simctl get_app_container <udid> com.pivi.dictus group.solutions.pivi.dictus`), an array of `TranscriptionRecord`, then relaunch: Home's recent rows and the sheet's list show it. Without a model Home hides its mic and the mode button but still shows the rows. For a Home with its mic and mode button but no download, also write `ouispr.downloadedModels` (data: the JSON `["openai_whisper-base"]`) and `ouispr.activeModel` in the App Group suite: captures only, the model cannot transcribe. The build must be signed (no `CODE_SIGNING_ALLOWED=NO`), or there is no App Group container.
- `Historique` also labels the Pro hub row and the switch on its page: use the Home tab first so the right one is on top.
