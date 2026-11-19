#!/bin/bash
# run.sh — Parakeet v3 against Parakeet Ultra on French dictation, on this Mac.
#
# 1. Synthesises sentences-fr.txt with the macOS French voices (16 kHz mono WAV).
# 2. Runs ParakeetBench once per model on that corpus.
# Results: build/parakeet-bench/<model>.tsv (one row per clip) and a summary on stdout.
#
# The voices are synthetic, so the absolute WER is optimistic; what counts is the gap
# between the two models on the same audio. For real voices, see README.md (FLEURS).
set -euo pipefail
cd "$(dirname "$0")"

OUT="${OUT:-../../build/parakeet-bench}"
VOICES=(${VOICES:-Thomas Jacques "Eddy (Français (France))" "Flo (Français (France))"})
mkdir -p "$OUT/corpus"

: > "$OUT/corpus/corpus.tsv"
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  n=$((n + 1))
  for v in "${VOICES[@]}"; do
    id="$(printf '%02d' "$n")-$(echo "$v" | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')"
    say -v "$v" -o "$OUT/corpus/$id.wav" --data-format=LEI16@16000 "$line"
    printf '%s\t%s\n' "$id" "$line" >> "$OUT/corpus/corpus.tsv"
  done
done < sentences-fr.txt

swift build -c release >/dev/null
for model in v3 ultra; do
  .build/release/ParakeetBench --model "$model" --corpus "$OUT/corpus" --out "$OUT/$model.tsv"
done
