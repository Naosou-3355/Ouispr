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
# parameters: --lambda --sigma --stretch --smoothing --budget --weakmargin
```

## Context bench (real sentences)

`context_bench.cpp` types every word of real French sentences, so the previous word
and the vocabulary's coverage of real text both count. Sentences: Universal Dependencies
French-GSD (CC BY-SA 4.0), downloaded at run time and never committed:

```bash
curl -LO https://raw.githubusercontent.com/UniversalDependencies/UD_French-GSD/master/fr_gsd-ud-test.conllu
curl -LO https://raw.githubusercontent.com/UniversalDependencies/UD_French-GSD/master/fr_gsd-ud-dev.conllu
clang++ -std=gnu++20 -O2 -I$A/include -Itools/typing-bench $A/src/*.cpp tools/typing-bench/context_bench.cpp -o /tmp/context-bench
/tmp/context-bench OuisprKeyboard/Resources fr_gsd-ud-test.conllu fr_gsd-ud-dev.conllu
```

Capitalised words inside a sentence are left out (the keyboard keeps them as proper
nouns). 1,892 sentences, 36,922 words. Results (24 Nov 2026, PR 19 pipeline, words right):

| tap noise | 40,000 words (before) | 99,000 words, long tail weak | not in dictionary |
|---|---|---|---|
| 0.20 | 96.09 % | **97.63 %** | 4.75 % → 2.10 % |
| 0.30 | 93.60 % | **95.25 %** | |
| 0.40 | 89.86 % | **91.64 %** | |

The isolated-word bench above moves by less than 0.1 pt with the larger dictionary.
Why "weak": trusting all 59,600 added words as typed let typos of common words land on
them and stay (isolated words: −0.5 pt at 0.30, −1.2 pt at 0.40). A weak word typed
exactly is kept unless a neighbour outscores it 1.5 times (`kWeakWordMargin`).

The bigram rerank the keyboard shipped (`TextPredictionEngine.spellCheck(_:previousWord:)`,
ported here as configs B, B2, B3) is removed: it cost 0.05 / 0.5 / 1.2 pt, almost all of
it from reordering the trie's own candidates by bigram score (B2); adding the n-gram
neighbours at edit distance 1 alone (B3) still cost 0.01 / 0.1 / 0.3 pt.

Measured but not shipped (words right, on top of config A):

| tap noise | previous word in key resizing (C) | + real-word fix (D) |
|---|---|---|
| 0.20 | +0.05 pt | +0.01 pt |
| 0.30 | +0.45 pt | +0.50 pt |
| 0.40 | +0.72 pt | +0.96 pt |

`--weakpick 1|2|3` restricts a non-word's correction to a weak word (see
`pickCorrection`). Mode 3 removes the missed-space regression of the 99,000-word
dictionary on the split-pass corpus (5 of 150 glued cases) but costs 0.2 / 0.75 pt on
sentences at 0.30 / 0.40; mode 2 costs 0.2 / 0.9 pt. Not shipped: typos outnumber
missed spaces.

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
- The French dictionary held 39,622 words; 99,219 since the weak long tail
  (`scripts/extend_fr_dictionary.py`).
