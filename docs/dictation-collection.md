# Collecte de dictées (banc de test)

Réglages › **Collecte de dictées**. Désactivé par défaut. Une fois activé, chaque dictée (clavier ou app) garde sur l'iPhone son audio et ses textes.

## Récupérer les données sur le Mac

1. Sur l'iPhone : Réglages › Collecte de dictées › **Exporter vers le Mac (AirDrop)**.
2. Choisir le Mac dans AirDrop. Le fichier `Ouispr-dictees-AAAA-MM-JJ-HHMM.zip` arrive dans **Téléchargements**.
3. Double-cliquer le zip dans le Finder pour l'extraire.

## Contenu du zip

```
DictationSamples/
  manifest.json          toutes les dictées, de la plus ancienne à la plus récente
  <uuid>/audio.wav       16 kHz, mono, PCM 16 bits
  <uuid>/sample.json     une dictée
```

Champs de `sample.json` (et de chaque entrée de `manifest.json`) :

| Champ | Sens |
|---|---|
| `id`, `createdAt` | identifiant, date ISO 8601 |
| `durationSeconds`, `sampleRate` | durée et fréquence de `audio.wav` |
| `language`, `engine`, `origin` | `fr`/`en`/`auto`, `PK` (Parakeet) ou `WK` (Whisper), `keyboard` ou `app` |
| `engineRaw` | sortie du moteur quand le vocabulaire l'a modifiée ; absent sinon |
| `raw` | texte transmis au nettoyage |
| `polished` | texte nettoyé (absent si le nettoyage n'a rien produit) |
| `correction` | la bonne version saisie à la main (absente si non corrigée) |

Comparer `polished` à `correction` mesure ce que toute la chaîne rate encore ; `audio.wav` permet de rejouer le moteur de transcription.
