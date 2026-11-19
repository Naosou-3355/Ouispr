# Politique de confidentialité — Ouispr

*Dernière mise à jour : 17 mars 2026*

## Résumé

Ouispr est un clavier iOS de dictée vocale **100 % hors ligne**. Aucune donnée vocale, aucun texte dicté et aucune frappe ne quittent votre appareil. Jamais.

## Ce que fait Ouispr

Ouispr convertit votre voix en texte directement sur votre iPhone grâce à WhisperKit (Apple CoreML). Tout le traitement se fait localement, sans connexion internet.

## Pourquoi Ouispr demande l'Accès complet

L'extension clavier iOS nécessite l'autorisation « Accès complet » (Full Access) **uniquement** pour accéder au microphone depuis le clavier. Sans cette autorisation, iOS interdit l'accès au micro dans une extension clavier.

Ouispr n'utilise **aucune** des autres fonctionnalités rendues possibles par l'Accès complet :
- **Pas d'accès réseau** — aucune requête HTTP, aucun envoi de données
- **Pas de lecture du presse-papiers** — le contenu copié reste privé
- **Pas d'enregistrement des frappes** — seul le texte dicté est inséré
- **Pas d'accès aux contacts, à la localisation ou aux photos**

## Données stockées localement

Les seules données enregistrées sur votre appareil sont :
- **Préférences utilisateur** — langue, modèle sélectionné, réglages (via App Group UserDefaults)
- **Fichiers de modèles** — modèles de reconnaissance vocale téléchargés (WhisperKit CoreML)
- **Journaux de débogage** — logs techniques pour diagnostiquer les problèmes (aucun contenu de transcription). Ils nomment l'application depuis laquelle une dictée a été lancée — par exemple Messages ou WhatsApp — jamais ce qui y a été dicté
- **Historique de dictée** (Ouispr Pro) — vos 200 dernières transcriptions, texte uniquement, jamais l'audio. Rien n'est enregistré sans Ouispr Pro actif (essai, abonnement ou achat à vie), et vous pouvez l'effacer à tout moment depuis Réglages > Transcription > Effacer l'historique, même après la fin de Ouispr Pro

Ces données ne quittent jamais votre appareil sauf si vous choisissez explicitement d'exporter les logs de débogage.

## Collecte de données

**Ouispr ne collecte aucune donnée.**

- Pas d'analytiques
- Pas de suivi (tracking)
- Pas de SDK tiers collectant des données
- Pas de publicité

L'étiquette de confidentialité App Store de Ouispr est : **« Données non collectées »**.

## Sécurité

Toutes les données restent sur votre appareil. Il n'y a pas de serveur Ouispr, pas de base de données cloud, pas de compte utilisateur.

## Contact

Pour toute question relative à la confidentialité :
**pierre@pivi.solutions**

---

# Privacy Policy — Ouispr

*Last updated: March 17, 2026*

## Summary

Ouispr is an iOS voice dictation keyboard that works **100% offline**. No voice data, no transcribed text, and no keystrokes ever leave your device. Period.

## What Ouispr does

Ouispr converts your voice to text directly on your iPhone using WhisperKit (Apple CoreML). All processing happens locally, with no internet connection required.

## Why Ouispr requests Full Access

The iOS keyboard extension requires "Full Access" permission **solely** to access the microphone from the keyboard. Without this permission, iOS blocks microphone access in keyboard extensions.

Ouispr does **not** use any of the other capabilities that Full Access enables:
- **No network access** — no HTTP requests, no data transmission
- **No clipboard reading** — your copied content stays private
- **No keystroke logging** — only dictated text is inserted
- **No access to contacts, location, or photos**

## Data stored locally

The only data saved on your device:
- **User preferences** — language, selected model, settings (via App Group UserDefaults)
- **Model files** — downloaded speech recognition models (WhisperKit CoreML)
- **Debug logs** — technical logs for diagnosing issues (no transcription content). They name the app a dictation was started from — Messages or WhatsApp, for instance — never what was dictated into it
- **Dictation history** (Ouispr Pro) — your last 200 transcriptions, text only, never the audio. Nothing is stored without active Ouispr Pro (trial, subscription or lifetime purchase), and you can erase it at any time from Settings > Transcription > Clear history, including after Ouispr Pro ends

This data never leaves your device unless you explicitly choose to export debug logs.

## Data collection

**Ouispr collects no data.**

- No analytics
- No tracking
- No third-party SDKs collecting data
- No advertising

Ouispr's App Store privacy nutrition label is: **"Data Not Collected"**.

## Security

All data stays on your device. There is no Ouispr server, no cloud database, no user account.

## Contact

For any privacy-related questions:
**pierre@pivi.solutions**
