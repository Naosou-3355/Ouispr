#!/usr/bin/env python3
"""
Build the French long-tail vocabulary added to the keyboard's trie as weak words.

fr_frequency.json (scripts/curate_fr_dictionary.py) keeps Lexique 3.83's top 40,000
words. On real French sentences (tools/typing-bench/context_bench.cpp) that leaves
4.75 % of the words typed unknown to the keyboard, everyday ones included
("plupart", "tandis", "cœur"), so a correct word gets "corrected" away.

This script lists the words to add:
  - every word seen 5 times or more in the OpenSubtitles 2018 French frequency list
    (hermitdave/FrequencyWords, CC BY-SA 4.0),
  - kept only if the French Hunspell dictionary accepts it as written in lowercase
    (Dicollecte 7.5 via wooorm/dictionaries, MPL 2.0; used as a filter, not shipped),
  - not already in fr_frequency.json,
  - with its count rescaled to fr_frequency.json's scale (median ratio on shared words).

Output: tools/dictionaries/fr_weak.json ({word: count}). Then rebuild the trie:

    python3 tools/dict_builder.py OuisprKeyboard/Resources/fr_frequency.json \\
        OuisprKeyboard/Resources/fr_spellcheck.dict --weak tools/dictionaries/fr_weak.json

Needs `pip install spylls` and network access. Takes about 3 minutes.
fr_frequency.json itself is NOT changed: FrequencyDictionary decodes it whole in the
keyboard extension, and only the mmap'd trie grows (400 KB -> about 1 MB).
"""

import json
import os
import re
import statistics
import sys
import tempfile
import urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FREQUENCY_JSON = os.path.join(ROOT, "OuisprKeyboard", "Resources", "fr_frequency.json")
OUTPUT = os.path.join(ROOT, "tools", "dictionaries", "fr_weak.json")

FREQUENCY_WORDS_URL = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/fr/fr_full.txt"
HUNSPELL_URL = "https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/fr/index.{}"

MIN_COUNT = 5
WORD = re.compile(r"^[a-zàâäçéèêëîïôöùûüÿœæ'-]+$")


def main() -> None:
    try:
        from spylls.hunspell import Dictionary
    except ImportError:
        sys.exit("pip install spylls")

    with tempfile.TemporaryDirectory() as tmp:
        subtitles = os.path.join(tmp, "fr_full.txt")
        urllib.request.urlretrieve(FREQUENCY_WORDS_URL, subtitles)
        for ext in ("dic", "aff"):
            urllib.request.urlretrieve(HUNSPELL_URL.format(ext), os.path.join(tmp, "fr." + ext))
        hunspell = Dictionary.from_files(os.path.join(tmp, "fr"))

        counts: dict[str, int] = {}
        with open(subtitles, encoding="utf-8") as f:
            for line in f:
                word, count = line.rsplit(" ", 1)
                if int(count) < MIN_COUNT:
                    break  # the list is sorted by count
                counts[word] = int(count)

    base = json.load(open(FREQUENCY_JSON, encoding="utf-8"))
    scale = statistics.median(base[w] / counts[w] for w in base if counts.get(w, 0) >= 1000)
    print(f"[INFO] {len(counts)} subtitle words, scale {scale:.4f}")

    weak = {}
    for word, count in counts.items():
        if word in base or len(word) < 2 or not WORD.match(word):
            continue
        if hunspell.lookup(word):
            weak[word] = max(1, int(count * scale))
    print(f"[INFO] {len(weak)} weak words")

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(weak.items(), key=lambda x: -x[1])), f, ensure_ascii=False, indent=0)
        f.write("\n")
    print(f"[DONE] {OUTPUT}")


if __name__ == "__main__":
    main()
