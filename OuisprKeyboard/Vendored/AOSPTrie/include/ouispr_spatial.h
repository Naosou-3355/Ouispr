// AOSP-inspired trie engine for Ouispr. Apache 2.0.
#ifndef OUISPR_SPATIAL_H
#define OUISPR_SPATIAL_H

#include <cstdint>

#include "ouispr_proximity.h"

namespace ouispr {

class Trie;

/// Where the finger actually landed, and what that says about each letter.
///
/// The proximity map scores a typo from the *key* that was produced: `r` typed for
/// `e` costs the same whether the finger hit the middle of `r` or its left edge. This
/// model keeps the touch point instead, the way Gboard's decoder does (a Gaussian per
/// key centre, Ouyang et al., "The Machine Intelligence Behind Gboard", Google
/// Research 2017), so a tap on the `e`|`r` border makes "e" and "r" almost equally
/// likely while a tap in the middle of `r` makes "e" expensive.
///
/// Coordinates are in key widths on both axes, measured on the rendered keyboard:
/// a row pitch of 1.35 means rows sit 1.35 key widths apart. Only letter keys are
/// installed; anything else keeps its proximity-map cost.
class SpatialModel {
public:
    static constexpr int MAX_KEYS = SUBSTITUTION_SLOT_COUNT;

    SpatialModel();

    /// Install the letter keys of the active layout: their characters, centres and the
    /// size of one key (all letter keys share it). Returns false and leaves the model
    /// untouched if the arguments are inconsistent.
    bool setKeys(const uint16_t* chars, const float* centerX, const float* centerY,
                 int count, float keyWidth, float keyHeight);

    bool hasKeys() const { return keyCount_ > 0; }

    /// Standard deviation of a touch around the key the user aimed at, in key widths.
    void setSigma(float sigma) { sigma_ = sigma; }

    /// Edit cost per (tap, letter), written to `out` as `n * SUBSTITUTION_SLOT_COUNT`
    /// floats, row-major by tap. Slots the model has no key for get -1, meaning "no
    /// opinion": the scorer then falls back to its proximity map.
    ///
    /// cost = lambda * (d(tap, c)^2 - d(tap, nearest)^2) / (2 sigma^2), clamped to
    /// [floor, 1]. The difference of squared distances is the Gaussian log-likelihood
    /// ratio between letter c and the best letter for that tap, so the key under the
    /// finger costs `floor` and a key one width away from a centred tap costs 1.
    void tapCosts(const float* tapX, const float* tapY, int n,
                  float lambda, float floor, float* out) const;

    /// Which key a touch most probably meant, given the letters already typed.
    ///
    /// `nextLetterWeights` holds P(next letter) per slot (any scale, need not sum to
    /// one; -1 or 0 everywhere means "no prediction"). The pick maximises
    /// log P(letter) + log N(touch | key centre), restricted to keys whose rectangle,
    /// grown by `maxStretch` key widths on every side, contains the touch. That bound
    /// is what keeps the effect invisible and safe: a tap well inside a key always
    /// produces that key, only border taps can be reassigned (the hidden hit-region
    /// resizing of Apple's US patent 8,232,973).
    ///
    /// `geometricKey` is the key under the finger. Returns the chosen character, or
    /// `geometricKey` when no neighbour beats it.
    uint16_t resolveTouch(float x, float y, uint16_t geometricKey,
                          const float* nextLetterWeights,
                          float maxStretch, float smoothing) const;

private:
    int keyCount_;
    uint16_t chars_[MAX_KEYS];
    float x_[MAX_KEYS];
    float y_[MAX_KEYS];
    float keyWidth_;
    float keyHeight_;
    float sigma_;
};

/// P(next letter | letters typed so far in the word), read from the dictionary.
///
/// Exact when the prefix is a dictionary prefix and its subtree is small enough to
/// walk within `nodeBudget`; otherwise falls back to a letter-bigram table built once
/// from the whole dictionary (`build`). Weights are word-frequency mass, so "qu" makes
/// `e`, `i` and `a` likely and `z` almost impossible.
class NextLetterModel {
public:
    NextLetterModel();

    /// Walk the whole trie once and fill the letter-bigram fallback. ~10 ms for 100k words.
    void build(const Trie& trie);

    bool isBuilt() const { return built_; }

    /// Fill `out` (SUBSTITUTION_SLOT_COUNT floats) with next-letter weights after
    /// `prefix`. Returns false when there is nothing useful to say (empty output).
    bool weights(const Trie& trie, const uint16_t* prefix, int len,
                 int nodeBudget, float* out) const;

private:
    bool built_;
    /// Row SLOT_COUNT is "start of word"; rows 0..SLOT_COUNT-1 the previous letter.
    float bigram_[SUBSTITUTION_SLOT_COUNT + 1][SUBSTITUTION_SLOT_COUNT];
};

} // namespace ouispr

#endif // OUISPR_SPATIAL_H
