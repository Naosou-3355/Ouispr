# Device bench

The Mac dictation bench (1,100 French clips, 10 synthetic voices), run on the iPhone:
Parakeet v3 through the app's own `ParakeetEngine`, then the polish pipeline on the
iPhone's Apple Intelligence model. It gives the iPhone's real times, comparable with
the Mac's, and the same quality counts.

## What runs where

- `OuisprApp/DeviceBench/DeviceBenchRunner.swift` is inside the app, dormant unless
  the app is launched with `--device-bench`. No new bundle id: a free Apple ID has ten
  App IDs a week and the bench must not spend one.
- For each clip, in order: transcription (timed), then the per-language French free
  polish exactly as `polish-harness show --prewarm` runs it on the Mac (prewarm, a 2 s
  pause standing for the recording, then the pipeline, timed). One row per clip is
  appended to `Documents/device-bench/out/results.tsv`, so a crash loses one clip and a
  relaunch resumes.
- Before the clips, `load.tsv` gets the model loads: Parakeet first load in the
  process (cold) and again while loaded (preloaded), its first inference, and one
  Apple Intelligence call cold then prewarmed.
- Each row has the engine time (`polish_ms`, the Mac's figure) and the whole pipeline
  after the speaker stops (`polish_wall_ms`, deterministic passes included);
  `e2e_ms` = transcription + that, end of speech → final text.
- The screen is kept awake while it runs. Each row carries the thermal state.

## Corpus

`gen.py` writes `cases.json` (seed 42), `synth.sh` speaks it with macOS `say` and
`ffmpeg` (16 kHz mono WAV, pink noise on some clips):

```bash
mkdir -p build/device-bench && cd build/device-bench
python3 ../../tools/device-bench/gen.py
../../tools/device-bench/synth.sh cases.json corpus
```

About 115 MB. It stays out of git (`build/`). For a shorter run, `subset.py` draws a
balanced subset (50 per category, spread over the ten voices, seeded):

```bash
python3 tools/device-bench/subset.py build/device-bench/cases.json build/device-bench/corpus build/device-bench/corpus-300
CORPUS=build/device-bench/corpus-300 tools/device-bench/run.sh push
```

## Run (about 1 h)

The iPhone on the cable, unlocked, Ouispr installed with `scripts/install-on-device.sh`
and Parakeet v3 downloaded in it, Apple Intelligence on.

```bash
tools/device-bench/run.sh push         # corpus → Ouispr's Documents
tools/device-bench/run.sh start fresh  # runs by itself; `start` alone resumes
tools/device-bench/run.sh wait         # polls every 2 min, pulls the results at the end
```

`run.sh status` prints the phase (`loading`, `running`, `done`, `failed` with its reason)
and the count.

## Score

```bash
python3 tools/device-bench/score.py build/device-bench/cases.json \
  --load build/device-bench/out/load.tsv --device build/device-bench/out/results.tsv --label iphone \
  --mac <v3.tsv> <polish-harness-show.txt> --label mac
```

Total = transcription of the whole clip + polish engine time (0 when the model is
skipped), the rule of the Mac bench. Median, p90, p95, max, % ≤ 1 s and ≤ 2 s, each
part apart, the check that cleanup p95 ≤ 1 s, then self-corrections, `:`, emails, one-line messages, hesitations.

## Not the same as the Mac

- The transcription goes through `ParakeetEngine.transcribe`, the app's path, which
  can retry a drifting decode (#623). The Mac bench called FluidAudio directly.
- The polish code is whatever the installed build carries. Compare runs of the same
  commit.
