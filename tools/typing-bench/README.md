# Typing bench

Measures how many words survive imprecise taps on the AZERTY keyboard, with and
without the two touch-aware features of `OuisprKeyboard/TouchHandling/SpatialTyping.swift`:

- **touch-aware correction**: the autocorrect scorer prices each letter from where the
  finger landed (Gboard's spatial model, [Google Research 2017](https://research.google/blog/the-machine-intelligence-behind-gboard/));
- **hidden key resizing**: a tap in the outer quarter of a key may go to the neighbour
  the dictionary expects next (Apple's adjustable hit regions, US patent 8,232,973,
  [AppleInsider](https://appleinsider.com/articles/12/07/31/apple_granted_patent_for_predictive_text_input_ui)).

It compiles the keyboard's own C++ (`OuisprKeyboard/Vendored/AOSPTrie/src`) with the
host compiler: no simulator, no Xcode project, about a minute.

```bash
# from the repository root, on the Mac
A=OuisprKeyboard/Vendored/AOSPTrie
clang++ -std=gnu++20 -O2 -I$A/include $A/src/*.cpp tools/typing-bench/bench.cpp -o /tmp/typing-bench
/tmp/typing-bench OuisprKeyboard/Resources 20000
# parameters: --lambda --sigma --stretch --smoothing --budget
```

## Model

- A tap is the centre of the intended key plus Gaussian noise (sigma in key widths, both
  axes), on the geometry measured from `assets/reference/ouispr-keyboard-letters.png`.
  Accented letters are long-pressed, hence exact.
- Correction = the trie path of `TextPredictionEngine.spellCheck`: a typed word that is
  in the dictionary is kept, anything else takes the scorer's best candidate.
- Three word sets: running text (drawn by corpus frequency), rare words (bottom half of
  the list, 5+ letters), and English words the French dictionary does not know (the risk
  case for resizing: a name or a foreign word must stay typable).

## Results (24 Nov 2026, 20,000 running words, parameters as shipped)

Words right after correction, and keystrokes right before it:

| tap noise | pipeline | running | rare | keys | unknown-word keys |
|---|---|---|---|---|---|
| 0.20 | today | 99.28 % | 98.32 % | 98.80 % | 98.74 % |
| 0.20 | both features | **99.51 %** | **98.80 %** | **99.57 %** | 98.78 % |
| 0.30 | today | 94.36 % | 89.38 % | 90.10 % | 89.84 % |
| 0.30 | both features | **96.01 %** | **92.80 %** | **95.52 %** | **92.20 %** |
| 0.40 | today | 86.60 % | 76.88 % | 76.80 % | 75.74 % |
| 0.40 | both features | **89.77 %** | **83.34 %** | **85.37 %** | **80.14 %** |

Wrong words drop by about 30 % at every noise level. Words the dictionary does not know
are never made harder to type. Cost: ~16 µs per letter tap for resizing.

Parameter choice (`AOSPTrieBridge.mm`): lambda 0.10 (0.25 and above made correction
worse at high noise), sigma 0.30, stretch 0.25 (0.35 and 0.50 add < 0.1 pt and start
costing unknown words at low noise), smoothing 0.30 (0.10 cost unknown words 0.2 pt at
low noise).

## Limits

- Simulated taps: no per-user offset, no thumb bias, no context. The real gain must be
  confirmed on the iPhone.
- A slip that produces another valid word ("fais" for "vais") is never corrected
  (the "already-valid" guard): only resizing can prevent it, upstream.
- The French dictionary holds 39,622 words.
