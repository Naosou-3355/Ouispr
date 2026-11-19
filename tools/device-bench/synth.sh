#!/bin/bash
# Speaks every case of cases.json with macOS `say` and writes a 16 kHz mono WAV per case,
# with pink noise mixed in where the case asks for it, plus corpus.tsv (id<TAB>text).
# Usage: tools/device-bench/synth.sh <cases.json> <out-dir>     (needs ffmpeg)
set -euo pipefail
CASES="$1"; OUT="$2"
mkdir -p "$OUT"; TMP="$(mktemp -d)"; : > "$OUT/corpus.tsv"
python3 -c "
import json,sys
for c in json.load(open(sys.argv[1])): print('\t'.join([c['id'],c['voice'],str(c['rate']),str(c['noise']),c['text']]))
" "$CASES" | while IFS=$'\t' read -r id voice rate noise text; do
  say -v "$voice" -r "$rate" -o "$TMP/$id.aiff" "$text"
  if [ "$noise" = "0" ]; then
    ffmpeg -loglevel error -y -i "$TMP/$id.aiff" -ar 16000 -ac 1 -c:a pcm_s16le "$OUT/$id.wav"
  else
    ffmpeg -loglevel error -y -i "$TMP/$id.aiff" -f lavfi -i "anoisesrc=color=pink:amplitude=$noise:sample_rate=22050" \
      -filter_complex "[0:a][1:a]amix=inputs=2:duration=first:normalize=0" -ar 16000 -ac 1 -c:a pcm_s16le "$OUT/$id.wav"
  fi
  rm "$TMP/$id.aiff"
  printf '%s\t%s\n' "$id" "$text" >> "$OUT/corpus.tsv"
done
rm -rf "$TMP"
