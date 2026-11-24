#!/usr/bin/env python3
"""Draws a balanced subset of the corpus: the same number of cases per category
(A self-corrections, B ":" announcements, C controls, D emails, E one-line messages,
G general), spread evenly over the ten voices. Seeded, so the same subset every run.

  subset.py <cases.json> <corpus-dir> <out-dir> [per-category=50]   -> 6 x 50 = 300 clips
"""
import json, os, random, shutil, sys
from collections import defaultdict

cases_path, corpus, out = sys.argv[1:4]
per_cat = int(sys.argv[4]) if len(sys.argv) > 4 else 50
cases = json.load(open(cases_path, encoding='utf-8'))
rng = random.Random(300)
picked = []
for cat in sorted({c['cat'] for c in cases}):
    by_voice = defaultdict(list)
    for c in cases:
        if c['cat'] == cat:
            by_voice[c['voice']].append(c)
    for v in by_voice.values():
        rng.shuffle(v)
    voices = sorted(by_voice)
    chosen, k = [], 0
    while len(chosen) < per_cat:  # round robin over voices
        v = by_voice[voices[k % len(voices)]]
        if v:
            chosen.append(v.pop())
        k += 1
    picked += chosen
picked.sort(key=lambda c: c['id'])
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'corpus.tsv'), 'w', encoding='utf-8') as f:
    for c in picked:
        shutil.copyfile(os.path.join(corpus, c['id'] + '.wav'), os.path.join(out, c['id'] + '.wav'))
        f.write(f"{c['id']}\t{c['text']}\n")
print(f"{len(picked)} clips -> {out}")
