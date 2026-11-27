# Dictation inside the app

- **ID:** `dictation.in-app`
- **Tier:** Gratuit (Free)
- **Targets:** OuisprApp
- **Screens:** `app.home`, `app.recording` (not captured) — see [screens.md](screens.md)

## Sub-features

- `dictation.start-in-app`: The round ink mic on Home (VoiceOver « Nouvelle dictée », #788) opens a full-screen recording. The mic flies to the recording screen's control row, at 75 % of its height: ✕ on its left while it runs; copy on its left and share on its right with a result (bare ink pictograms on 44 pt targets). The mic is always a full disc; the stop square is drawn inside it. The listening state shows only once the microphone delivers audio, and a silence under 3 s at the start does not end the recording; every stop logs its cause (`dictationStopped cause=… duration=… peak=…`). With a result the character plays the drop, laughing eyes, then rest, on the result screen itself; « Terminé » shows once the last word is sharp. Back on Home the new dictation is the first recent row; nothing flies. Home, the history and this screen share a still background (`OuisprBackdrop`): a faint accent veil at the top, never animated.
- `dictation.copy-last`: The last transcription card copies its text on tap.
- `dictation.download-prompt`: Without a model, Home asks to download one instead of offering a dictation.
- `dictation.from-widget`: A dictation started from the widget opens the same in-app recording.

## How to get to it (user POV)

1. Open Ouispr, tab Accueil.
2. Tap the round mic above « Balayez pour l'historique », speak, tap the stop button.
3. Tap the "Last transcription" card to copy the text.

## Driving it with axe + Argent

```bash
.claude/skills/verify-ouispr-ios/scripts/launch.sh --skip-onboarding
.claude/skills/verify-ouispr-ios/scripts/drive.sh tab Accueil
argent run describe --udid <udid>      # without a model: « Télécharger un modèle pour commencer »
```

With a model installed (see `models.transcription`), `.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-id home.newDictation` (or `tap-label "Nouvelle dictée"`) opens the recording screen and `.claude/skills/verify-ouispr-ios/scripts/drive.sh tap-label "Arrêter l'enregistrement"` stops it — only when the task accepts recording the Mac's microphone.

## Gotchas

- **Not drivable in the simulator without recording the room:** the dictation itself. Leave it to a physical iPhone unless the task explicitly accepts a Mac-microphone capture.
- `app.home` captured here is the no-model state; the mic does not exist until a model is downloaded. With a model, the mic stays pinned at the bottom and the content above it hangs from the top, then scrolls when it does not fit (short screen, the iPhone layout an iPad runs in, large Dynamic Type); while it scrolls, a swipe up that starts on it scrolls instead of opening the history.
