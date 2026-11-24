// AOSP-inspired trie engine for Ouispr. Apache 2.0.
#include "ouispr_spatial.h"
#include "ouispr_trie.h"
#include "ouispr_trie_format.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace ouispr {

// --- Spatial model ---

SpatialModel::SpatialModel()
    : keyCount_(0), keyWidth_(1.0f), keyHeight_(1.0f), sigma_(0.3f) {}

bool SpatialModel::setKeys(const uint16_t* chars, const float* centerX, const float* centerY,
                           int count, float keyWidth, float keyHeight) {
    if (!chars || !centerX || !centerY || count <= 0 || count > MAX_KEYS) return false;
    if (!(keyWidth > 0.0f) || !(keyHeight > 0.0f)) return false;
    for (int i = 0; i < count; i++) {
        if (substitutionSlot(chars[i]) < 0) return false;
    }
    for (int i = 0; i < count; i++) {
        chars_[i] = static_cast<uint16_t>(
            (chars[i] >= 'A' && chars[i] <= 'Z') ? chars[i] - 'A' + 'a' : chars[i]);
        x_[i] = centerX[i];
        y_[i] = centerY[i];
    }
    keyCount_ = count;
    keyWidth_ = keyWidth;
    keyHeight_ = keyHeight;
    return true;
}

void SpatialModel::tapCosts(const float* tapX, const float* tapY, int n,
                            float lambda, float floor, float* out) const {
    const int slots = SUBSTITUTION_SLOT_COUNT;
    std::fill(out, out + n * slots, -1.0f);
    if (keyCount_ == 0 || n <= 0) return;

    const float twoSigma2 = 2.0f * sigma_ * sigma_;
    for (int t = 0; t < n; t++) {
        float* row = out + t * slots;
        float d2[MAX_KEYS];
        float best = 1e9f;
        for (int k = 0; k < keyCount_; k++) {
            float dx = tapX[t] - x_[k];
            float dy = tapY[t] - y_[k];
            d2[k] = dx * dx + dy * dy;
            best = std::min(best, d2[k]);
        }
        for (int k = 0; k < keyCount_; k++) {
            float c = lambda * (d2[k] - best) / twoSigma2;
            row[substitutionSlot(chars_[k])] = std::min(1.0f, std::max(floor, c));
        }
    }
}

uint16_t SpatialModel::resolveTouch(float x, float y, uint16_t geometricKey,
                                    const float* nextLetterWeights,
                                    float maxStretch, float smoothing) const {
    if (keyCount_ == 0 || !nextLetterWeights) return geometricKey;

    // Normalise the prediction over the installed keys and mix in a uniform floor, so a
    // letter the dictionary has never seen after this prefix (a name, a typo being
    // typed on purpose) stays reachable from a border tap.
    float total = 0.0f;
    for (int k = 0; k < keyCount_; k++) {
        float w = nextLetterWeights[substitutionSlot(chars_[k])];
        if (w > 0.0f) total += w;
    }
    if (!(total > 0.0f)) return geometricKey;

    const float twoSigma2 = 2.0f * sigma_ * sigma_;
    const float halfW = 0.5f * keyWidth_ + maxStretch;
    const float halfH = 0.5f * keyHeight_ + maxStretch;
    const float uniform = 1.0f / static_cast<float>(keyCount_);

    uint16_t bestChar = geometricKey;
    float bestScore = -1e30f;
    bool geometricSeen = false;
    for (int k = 0; k < keyCount_; k++) {
        float dx = x - x_[k];
        float dy = y - y_[k];
        bool isGeometric = chars_[k] == geometricKey;
        // Only the key under the finger and neighbours whose grown rectangle reaches the
        // touch may compete.
        if (!isGeometric && (std::fabs(dx) > halfW || std::fabs(dy) > halfH)) continue;
        float w = std::max(0.0f, nextLetterWeights[substitutionSlot(chars_[k])]);
        float p = (1.0f - smoothing) * (w / total) + smoothing * uniform;
        float score = std::log(p) - (dx * dx + dy * dy) / twoSigma2;
        if (isGeometric) geometricSeen = true;
        // Ties keep the key under the finger.
        if (score > bestScore || (score == bestScore && isGeometric)) {
            bestScore = score;
            bestChar = chars_[k];
        }
    }
    return geometricSeen ? bestChar : geometricKey;
}

// --- Next-letter model ---

namespace {

uint32_t nodeByteSize(const TrieNode& node) {
    // Mirrors computeNodeSize() in ouispr_scorer.cpp.
    uint32_t sz = 1;
    if (node.flags & FLAG_MULTI_CHAR) sz += 1;
    sz += node.charCount * 2;
    if (node.flags & FLAG_TERMINAL) sz += 2;
    int ptrSize = childrenPtrSize(node.flags);
    if (ptrSize > 0) sz += 1 + ptrSize;
    return sz;
}

/// Frequencies are stored as 65535 * ln(1 + count) / ln(1 + maxCount) (dict_builder.py).
/// Undo that so masses add up like counts.
double countFromStored(uint16_t stored, double logMax) {
    if (stored == 0) return 0.0;
    return std::exp(static_cast<double>(stored) / 65535.0 * logMax) - 1.0;
}

uint16_t lower(uint16_t c) {
    return (c >= 'A' && c <= 'Z') ? static_cast<uint16_t>(c - 'A' + 'a') : c;
}

uint16_t charAt(const TrieNode& node, int i) {
    uint16_t c;
    std::memcpy(&c, &node.chars[i], 2);
    return c;
}

template <typename Visit>
void forEachChild(const Trie& trie, const TrieNode& node, Visit visit) {
    if (childrenPtrSize(node.flags) == 0 || node.childCount == 0) return;
    uint32_t off = node.childrenOffset;
    for (int i = 0; i < node.childCount && off < trie.fileSize(); i++) {
        TrieNode child = trie.readNode(off);
        if (child.charCount == 0) break;
        if (!visit(child)) return;
        off += nodeByteSize(child);
    }
}

template <typename Visit>
void forEachRoot(const Trie& trie, Visit visit) {
    uint32_t off = HEADER_SIZE;
    int count = trie.rootChildCount();
    for (int i = 0; i < count && off < trie.fileSize(); i++) {
        TrieNode node = trie.readNode(off);
        if (node.charCount == 0) break;
        if (!visit(node)) return;
        off += nodeByteSize(node);
    }
}

/// Word-frequency mass under `node` (itself included). Decrements `budget` per node and
/// gives up (returns -1) when it reaches zero.
double subtreeMass(const Trie& trie, const TrieNode& node, double logMax, int& budget) {
    if (--budget < 0) return -1.0;
    double mass = (node.flags & FLAG_TERMINAL) ? countFromStored(node.frequency, logMax) : 0.0;
    bool exhausted = false;
    forEachChild(trie, node, [&](const TrieNode& child) {
        double m = subtreeMass(trie, child, logMax, budget);
        if (m < 0.0) { exhausted = true; return false; }
        mass += m;
        return true;
    });
    return exhausted ? -1.0 : mass;
}

/// Accumulate letter bigrams (including the start-of-word row) over the whole trie.
void accumulateBigrams(const Trie& trie, const TrieNode& node, int prevSlot, double logMax,
                       double (*table)[SUBSTITUTION_SLOT_COUNT], double& massOut) {
    double mass = (node.flags & FLAG_TERMINAL) ? countFromStored(node.frequency, logMax) : 0.0;
    forEachChild(trie, node, [&](const TrieNode& child) {
        double m = 0.0;
        int last = substitutionSlot(lower(charAt(node, node.charCount - 1)));
        accumulateBigrams(trie, child, last, logMax, table, m);
        mass += m;
        return true;
    });
    // Every word under this node spells the node's characters in sequence: credit each
    // internal transition with the whole subtree mass.
    int prev = prevSlot;
    for (int i = 0; i < node.charCount; i++) {
        int slot = substitutionSlot(lower(charAt(node, i)));
        if (slot >= 0 && prev >= -1) {
            int row = prev < 0 ? SUBSTITUTION_SLOT_COUNT : prev;
            table[row][slot] += mass;
        }
        prev = slot < 0 ? -2 : slot;  // -2: unknown character, stop crediting
    }
    massOut = mass;
}

}  // namespace

NextLetterModel::NextLetterModel() : built_(false) {
    std::memset(bigram_, 0, sizeof(bigram_));
}

void NextLetterModel::build(const Trie& trie) {
    std::vector<double> table((SUBSTITUTION_SLOT_COUNT + 1) * SUBSTITUTION_SLOT_COUNT, 0.0);
    auto* rows = reinterpret_cast<double (*)[SUBSTITUTION_SLOT_COUNT]>(table.data());
    double logMax = std::log(1.0 + static_cast<double>(trie.maxFreq()));
    forEachRoot(trie, [&](const TrieNode& node) {
        double m = 0.0;
        accumulateBigrams(trie, node, -1, logMax, rows, m);
        return true;
    });
    for (int r = 0; r <= SUBSTITUTION_SLOT_COUNT; r++) {
        for (int c = 0; c < SUBSTITUTION_SLOT_COUNT; c++) {
            bigram_[r][c] = static_cast<float>(rows[r][c]);
        }
    }
    built_ = true;
}

bool NextLetterModel::weights(const Trie& trie, const uint16_t* prefix, int len,
                              int nodeBudget, float* out) const {
    std::fill(out, out + SUBSTITUTION_SLOT_COUNT, 0.0f);
    if (!trie.rootData()) return false;

    auto fallback = [&]() {
        if (!built_) return false;
        int row = SUBSTITUTION_SLOT_COUNT;
        if (len > 0) {
            int slot = substitutionSlot(lower(prefix[len - 1]));
            if (slot < 0) return false;
            row = slot;
        }
        bool any = false;
        for (int c = 0; c < SUBSTITUTION_SLOT_COUNT; c++) {
            out[c] = bigram_[row][c];
            any = any || out[c] > 0.0f;
        }
        return any;
    };

    if (len == 0) return fallback();

    // Walk the prefix down the trie.
    TrieNode node;
    bool found = false;
    int consumed = 0;
    int posInNode = 0;
    forEachRoot(trie, [&](const TrieNode& candidate) {
        if (lower(charAt(candidate, 0)) == lower(prefix[0])) { node = candidate; found = true; return false; }
        return true;
    });
    if (!found) return fallback();
    while (true) {
        while (posInNode < node.charCount && consumed < len) {
            if (lower(charAt(node, posInNode)) != lower(prefix[consumed])) return fallback();
            posInNode++;
            consumed++;
        }
        if (consumed == len) break;
        // Node exhausted, prefix not: descend into the matching child.
        bool descended = false;
        forEachChild(trie, node, [&](const TrieNode& child) {
            if (lower(charAt(child, 0)) == lower(prefix[consumed])) {
                node = child; descended = true; return false;
            }
            return true;
        });
        if (!descended) return fallback();
        posInNode = 0;
    }

    // Prefix ends inside a multi-character node: exactly one continuation.
    if (posInNode < node.charCount) {
        int slot = substitutionSlot(lower(charAt(node, posInNode)));
        if (slot < 0) return fallback();
        out[slot] = 1.0f;
        return true;
    }

    double logMax = std::log(1.0 + static_cast<double>(trie.maxFreq()));
    int budget = nodeBudget;
    bool any = false;
    bool exhausted = false;
    forEachChild(trie, node, [&](const TrieNode& child) {
        int slot = substitutionSlot(lower(charAt(child, 0)));
        double m = subtreeMass(trie, child, logMax, budget);
        if (m < 0.0) { exhausted = true; return false; }
        if (slot >= 0 && m > 0.0) { out[slot] += static_cast<float>(m); any = true; }
        return true;
    });
    if (exhausted) return fallback();
    return any;
}

}  // namespace ouispr
