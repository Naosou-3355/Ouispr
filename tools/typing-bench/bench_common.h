// Shared by bench.cpp and context_bench.cpp: UTF-16 helpers, the frequency-file
// reader, the rendered AZERTY geometry and the keyboard's static tables.
#pragma once
#include "ouispr_proximity.h"
#include "ouispr_scorer.h"

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
