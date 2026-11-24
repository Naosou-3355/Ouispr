// Shared by bench.cpp and context_bench.cpp: UTF-16 helpers, the frequency-file
// reader, the rendered AZERTY geometry and the keyboard's static tables.
#pragma once
#include "ouispr_proximity.h"
#include "ouispr_scorer.h"
#include "ouispr_trie.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

using namespace ouispr;

// --- UTF-8 <-> UTF-16 (BMP only, enough for the languages shipped) ---

inline std::u16string toU16(const std::string& s) {
    std::u16string out;
    for (size_t i = 0; i < s.size();) {
        unsigned char c = s[i];
        if (c < 0x80) { out.push_back(c); i += 1; }
        else if ((c >> 5) == 6 && i + 1 < s.size()) { out.push_back(((c & 0x1F) << 6) | (s[i + 1] & 0x3F)); i += 2; }
        else if ((c >> 4) == 14 && i + 2 < s.size()) {
            out.push_back(((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F)); i += 3;
        } else { out.push_back(0xFFFD); i += 1; }
    }
    return out;
}

// --- {"word": count, ...} reader (the keyboard's frequency files are flat) ---

inline std::string toU8(const std::u16string& s) {
    std::string out;
    for (char16_t c : s) {
        if (c < 0x80) out.push_back(static_cast<char>(c));
        else if (c < 0x800) { out.push_back(0xC0 | (c >> 6)); out.push_back(0x80 | (c & 0x3F)); }
        else { out.push_back(0xE0 | (c >> 12)); out.push_back(0x80 | ((c >> 6) & 0x3F)); out.push_back(0x80 | (c & 0x3F)); }
    }
    return out;
}

inline std::vector<std::pair<std::string, double>> readFrequency(const std::string& path) {
    std::ifstream f(path);
    std::stringstream ss; ss << f.rdbuf();
    std::string s = ss.str();
    std::vector<std::pair<std::string, double>> out;
    size_t i = 0;
    while ((i = s.find('"', i)) != std::string::npos) {
        size_t j = s.find('"', i + 1);
        if (j == std::string::npos) break;
        std::string w = s.substr(i + 1, j - i - 1);
        size_t colon = s.find(':', j);
        if (colon == std::string::npos) break;
        double count = std::strtod(s.c_str() + colon + 1, nullptr);
        out.emplace_back(w, count);
        i = s.find_first_of(",}", colon);
        if (i == std::string::npos) break;
    }
    return out;
}

// --- Geometry ---

struct Key { char16_t ch; float x, y; };

inline const float ROW_PITCH = 1.35f;

inline std::vector<Key> renderedAzerty() {
    std::vector<Key> keys;
    const char* rows[3] = {"azertyuiop", "qsdfghjklm", "wxcvbn'"};
    const float offsets[3] = {0.0f, 0.0f, 1.5f};
    for (int r = 0; r < 3; r++)
        for (int k = 0; rows[r][k]; k++)
            keys.push_back({static_cast<char16_t>(rows[r][k]), offsets[r] + k, r * ROW_PITCH});
    return keys;
}

/// The static table OuisprCore's KeyboardProximity installs today (nominal geometry,
/// row index as y, distance / 2.5 clamped to 1).
inline void installStaticProximity(ProximityMap& map) {
    const char* rows[3] = {"azertyuiop", "qsdfghjklm", "wxcvbn"};
    const float offsets[3] = {0.0f, 0.25f, 0.75f};
    std::vector<uint16_t> chars; std::vector<float> xs, ys;
    for (int r = 0; r < 3; r++)
        for (int k = 0; rows[r][k]; k++) { chars.push_back(rows[r][k]); xs.push_back(offsets[r] + k); ys.push_back(r); }
    int n = chars.size();
    std::vector<float> d(n * n);
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            float dx = xs[i] - xs[j], dy = ys[i] - ys[j];
            d[i * n + j] = i == j ? 0.0f : std::min(1.0f, std::sqrt(dx * dx + dy * dy) / 2.5f);
        }
    map.setTable(chars.data(), n, d.data());
}

/// AccentRelation (OuisprCore): base <-> accent 0.15, accent <-> accent 0.20, French set.
inline void installAccents(AccentCostTable& table) {
    std::map<char16_t, char16_t> base = {
        {u'é', 'e'}, {u'è', 'e'}, {u'ê', 'e'}, {u'ë', 'e'}, {u'à', 'a'}, {u'â', 'a'},
        {u'ù', 'u'}, {u'û', 'u'}, {u'ô', 'o'}, {u'î', 'i'}, {u'ï', 'i'}, {u'ç', 'c'}};
    std::vector<uint16_t> from, to; std::vector<float> cost;
    for (auto& [a, b] : base) {
        from.push_back(b); to.push_back(a); cost.push_back(0.15f);
        from.push_back(a); to.push_back(b); cost.push_back(0.15f);
        for (auto& [a2, b2] : base)
            if (a2 != a && b2 == b) { from.push_back(a); to.push_back(a2); cost.push_back(0.20f); }
    }
    table.setPairs(from.data(), to.data(), cost.data(), from.size());
}

inline char16_t baseOf(char16_t c) {
    static const std::map<char16_t, char16_t> m = {
        {u'é', 'e'}, {u'è', 'e'}, {u'ê', 'e'}, {u'ë', 'e'}, {u'à', 'a'}, {u'â', 'a'},
        {u'ù', 'u'}, {u'û', 'u'}, {u'ô', 'o'}, {u'î', 'i'}, {u'ï', 'i'}, {u'ç', 'c'}};
    auto it = m.find(c);
    return it == m.end() ? c : it->second;
}

/// Key under the finger: nearest row, then nearest key in that row (keys tile their row).
inline const Key& geometricKey(const std::vector<Key>& keys, float x, float y) {
    int row = std::clamp(static_cast<int>(std::lround(y / ROW_PITCH)), 0, 2);
    const Key* best = nullptr; float bd = 1e9f;
    for (const Key& k : keys) {
        if (std::lround(k.y / ROW_PITCH) != row) continue;
        float d = std::fabs(k.x - x);
        if (d < bd) { bd = d; best = &k; }
    }
    return *best;
}

inline bool isTypable(const std::u16string& w) {
    if (w.size() < 2) return false;
    for (char16_t c : w) {
        char16_t b = baseOf(c);
        if (!(b >= 'a' && b <= 'z')) return false;
    }
    return true;
}


/// How much better than the exact word a candidate must score to replace a weak word
/// typed exactly (kWeakWordMargin in AOSPTrieBridge.mm).
inline float gWeakMargin = 1.5f;

/// Whether a weak word typed exactly stays: the scorer's winner is the word itself, or
/// beats it by less than gWeakMargin.
inline bool keepsWeakWord(const std::vector<Candidate>& cands, const std::u16string& typed) {
    if (cands.empty()) return true;
    float exact = 0.0f;
    for (const auto& c : cands) if (toU16(c.word) == typed) exact = std::max(exact, c.score);
    return cands[0].score <= gWeakMargin * exact;
}

inline int editDistance(const std::u16string& a, const std::u16string& b) {
    std::vector<int> prev(b.size() + 1), cur(b.size() + 1);
    for (size_t j = 0; j <= b.size(); j++) prev[j] = j;
    for (size_t i = 1; i <= a.size(); i++) {
        cur[0] = i;
        for (size_t j = 1; j <= b.size(); j++)
            cur[j] = std::min({prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)});
        std::swap(prev, cur);
    }
    return prev[b.size()];
}

/// How a non-word's correction treats weak words (the dictionary's long tail).
/// 0: the scorer's winner. 1: a trusted candidate wins unless the weak winner beats it
/// by more than gWeakPickMargin. 2: a weak winner only at edit distance 1, else the best
/// trusted candidate, else nothing. 3: 1, and a weak winner with no trusted rival only at
/// edit distance 1.
inline int gWeakPick = 0;
inline float gWeakPickMargin = 1.5f;

inline std::u16string pickCorrection(const Trie& trie, const std::vector<Candidate>& cands, const std::u16string& typed) {
    if (cands.empty()) return typed;
    std::u16string top = toU16(cands[0].word);
    auto trusted = [&](const std::u16string& w) {
        return trie.wordIsTrusted(reinterpret_cast<const uint16_t*>(w.data()), w.size());
    };
    if (gWeakPick == 0 || trusted(top)) return top;
    const Candidate* bestTrusted = nullptr;
    for (const auto& c : cands) { if (trusted(toU16(c.word))) { bestTrusted = &c; break; } }
    if (gWeakPick == 2) {
        if (editDistance(typed, top) <= 1) return top;
        return bestTrusted ? toU16(bestTrusted->word) : typed;
    }
    if (bestTrusted && cands[0].score <= gWeakPickMargin * bestTrusted->score) return toU16(bestTrusted->word);
    if (gWeakPick == 3 && !bestTrusted && editDistance(typed, top) > 1) return typed;
    return top;
}
