# Parakeet v3 vs Parakeet Ultra, French

Measurement only: the app still ships Parakeet v3 on FluidAudio 0.15.8. Ultra
(`AsrModelVersion.ultra`, a post-trained v3 with the same architecture) needs FluidAudio 0.18.

## Results (2026-11-19, MacBook Pro M3 Max, Neural Engine)

| Set | v3 WER | Ultra WER | v3 latency | Ultra latency |
|---|---:|---:|---:|---:|
| FLEURS fr_fr, 350 real voices (~10 s each) | 6.3 % | **5.6 %** | RTFx 136× | RTFx 136× |
| Dictation, 40 sentences × 4 synthetic voices (~3.4 s, 1808 words) | **3.15 %** | 3.98 % | 47 ms median | 47 ms median |

- Both models are equally fast; the gap is in accuracy only, and it is small and goes both ways:
  Ultra is better on real voices (−0.7 point, as FluidAudio's own FLEURS figure, −0.8),
  v3 on the synthetic dictation set (+0.8 point, ~15 words out of 1808).
- First load (Core ML compilation): v3 15 s, Ultra 10 s; then 0.1 s from the cache.
- Ultra's encoder is 595 MB against 445 MB for v3.
- Not measured on iPhone: that needs the app on FluidAudio 0.18 first. FluidAudio reports
  Ultra at speed parity with v3 on the Neural Engine.

## Run

```bash
tools/parakeet-bench/run.sh            # dictation set: say → WAV, then both models
```

`run.sh` writes the clips and `build/parakeet-bench/{v3,ultra}.tsv` (one row per clip:
reference, hypothesis, errors, latency). Each clip is transcribed as `ParakeetEngine` does
it: fresh decoder state, no `language:`, one chunk at a time, after one untimed warm-up.
WER ignores case, punctuation, hyphens, ligatures and whether a number is in digits or words.

FLEURS uses FluidAudio's own CLI (it downloads the dataset):

```bash
git clone --depth 1 --branch v0.18.3 https://github.com/FluidInference/FluidAudio.git
cd FluidAudio && swift build -c release --product fluidaudiocli
.build/release/fluidaudiocli fleurs-benchmark --languages fr_fr --samples 350 --model-version v3
.build/release/fluidaudiocli fleurs-benchmark --languages fr_fr --samples 350 --model-version ultra
```
