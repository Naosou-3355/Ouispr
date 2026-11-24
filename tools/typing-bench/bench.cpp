// Typing bench: how many words survive imprecise taps, with and without the spatial
// model (touch-aware correction) and the hidden key resizing (touch resolution).
//
// Runs the keyboard's own C++ trie, scorer and spatial model on the Mac (or any host
// with a C++17 compiler): no simulator, no Xcode project. See README.md.
//
// Model of a tap: the centre of the intended key plus Gaussian noise (sigma in key
// widths, same on both axes), on the AZERTY geometry measured from the rendered
// keyboard (assets/reference/ouispr-keyboard-letters.png): rows 1.35 key widths apart,
// the two upper rows flush left, w..n starting 1.5 keys in, the apostrophe after n.
// Accented letters are typed by long press and therefore exact.
//
// What the correction step models: the trie path of TextPredictionEngine.spellCheck —
// a typed word that exists in the dictionary is kept ("already-valid"), anything else
// takes the scorer's best candidate. The split pass, overrides and contractions are
// not modelled; they act the same in every pipeline compared here.
#include "ouispr_proximity.h"
#include "ouispr_scorer.h"
#include "ouispr_spatial.h"
#include "ouispr_trie.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <random>
#include <sstream>
#include <string>
#include <vector>

using namespace ouispr;

// --- UTF-8 <-> UTF-16 (BMP only, enough for the languages shipped) ---

static std::u16string toU16(const std::string& s) {
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

static std::vector<std::pair<std::string, double>> readFrequency(const std::string& path) {
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

static const float ROW_PITCH = 1.35f;

static std::vector<Key> renderedAzerty() {
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
static void installStaticProximity(ProximityMap& map) {
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
static void installAccents(AccentCostTable& table) {
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

static char16_t baseOf(char16_t c) {
    static const std::map<char16_t, char16_t> m = {
        {u'é', 'e'}, {u'è', 'e'}, {u'ê', 'e'}, {u'ë', 'e'}, {u'à', 'a'}, {u'â', 'a'},
        {u'ù', 'u'}, {u'û', 'u'}, {u'ô', 'o'}, {u'î', 'i'}, {u'ï', 'i'}, {u'ç', 'c'}};
    auto it = m.find(c);
    return it == m.end() ? c : it->second;
}

/// Key under the finger: nearest row, then nearest key in that row (keys tile their row).
static const Key& geometricKey(const std::vector<Key>& keys, float x, float y) {
    int row = std::clamp(static_cast<int>(std::lround(y / ROW_PITCH)), 0, 2);
    const Key* best = nullptr; float bd = 1e9f;
    for (const Key& k : keys) {
        if (std::lround(k.y / ROW_PITCH) != row) continue;
        float d = std::fabs(k.x - x);
        if (d < bd) { bd = d; best = &k; }
    }
    return *best;
}

// --- Bench ---

struct Config {
    const char* name;
    bool spatialCorrection;
    bool dynamicKeys;
};

struct Params {
    float lambda = 0.10f;     // tap cost scale (kTapCostLambda)
    float sigmaModel = 0.30f; // sigma the model assumes (kTouchSigma)
    float stretch = 0.25f;    // max hidden growth of a key, key widths (kMaxKeyStretch)
    float smoothing = 0.30f;  // uniform floor in next-letter prior (kNextLetterSmoothing)
    int budget = 4000;        // node budget for exact next-letter mass (kNextLetterNodeBudget)
};

struct Outcome { int words = 0, wordsOk = 0, keys = 0, keysOk = 0; double correctUs = 0, resolveUs = 0; int corrections = 0, resolves = 0; };

static bool isTypable(const std::u16string& w) {
    if (w.size() < 2) return false;
    for (char16_t c : w) {
        char16_t b = baseOf(c);
        if (!(b >= 'a' && b <= 'z')) return false;
    }
    return true;
}

static Outcome run(const Trie& trie, const Scorer& scorer, const SpatialModel& spatial,
                   const NextLetterModel& next, const std::vector<Key>& keys,
                   const std::vector<std::u16string>& words, float sigmaTrue,
                   const Config& cfg, const Params& p, bool correct, unsigned seed) {
    std::mt19937 rng(seed);
    std::normal_distribution<float> noise(0.0f, sigmaTrue);
    std::map<char16_t, const Key*> byChar;
    for (const Key& k : keys) byChar[k.ch] = &k;
    Outcome o;
    std::vector<float> weights(SUBSTITUTION_SLOT_COUNT);
    for (const auto& target : words) {
        std::u16string typed;
        std::vector<float> tx, ty;
        std::vector<bool> hasTap;
        for (char16_t c : target) {
            if (baseOf(c) != c) {  // long press: exact
                typed.push_back(c); tx.push_back(0); ty.push_back(0); hasTap.push_back(false);
                continue;
            }
            const Key* aim = byChar[c];
            float x = aim->x + noise(rng), y = aim->y + noise(rng);
            const Key& g = geometricKey(keys, x, y);
            char16_t out = g.ch;
            if (cfg.dynamicKeys && g.ch != '\'') {
                auto t0 = std::chrono::steady_clock::now();
                bool ok = next.weights(trie, reinterpret_cast<const uint16_t*>(typed.data()), typed.size(), p.budget, weights.data());
                if (ok) out = spatial.resolveTouch(x, y, g.ch, weights.data(), p.stretch, p.smoothing);
                o.resolveUs += std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t0).count();
                o.resolves++;
            }
            typed.push_back(out); tx.push_back(x); ty.push_back(y); hasTap.push_back(true);
        }
        for (size_t i = 0; i < target.size(); i++) { o.keys++; if (typed[i] == target[i]) o.keysOk++; }

        std::u16string final = typed;
        bool hasApostrophe = typed.find(u'\'') != std::u16string::npos;
        if (correct && !hasApostrophe &&
            !trie.wordExists(reinterpret_cast<const uint16_t*>(typed.data()), typed.size())) {
            std::vector<float> costs;
            const float* costPtr = nullptr;
            auto t0 = std::chrono::steady_clock::now();
            if (cfg.spatialCorrection) {
                costs.assign(typed.size() * SUBSTITUTION_SLOT_COUNT, -1.0f);
                spatial.tapCosts(tx.data(), ty.data(), typed.size(), p.lambda, 0.0f, costs.data());
                for (size_t i = 0; i < typed.size(); i++)
                    if (!hasTap[i]) std::fill(costs.begin() + i * SUBSTITUTION_SLOT_COUNT, costs.begin() + (i + 1) * SUBSTITUTION_SLOT_COUNT, -1.0f);
                costPtr = costs.data();
            }
            auto cands = scorer.correct(trie, reinterpret_cast<const uint16_t*>(typed.data()), typed.size(), 2.0f, 5, costPtr);
            o.correctUs += std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t0).count();
            o.corrections++;
            if (!cands.empty()) final = toU16(cands[0].word);
        }
        o.words++;
        if (final == target) o.wordsOk++;
    }
    return o;
}

int main(int argc, char** argv) {
    std::string resources = argc > 1 ? argv[1] : "OuisprKeyboard/Resources";
    int n = argc > 2 ? std::atoi(argv[2]) : 20000;
    Params p;
    for (int i = 3; i + 1 < argc; i += 2) {
        std::string k = argv[i]; float v = std::atof(argv[i + 1]);
        if (k == "--lambda") p.lambda = v; else if (k == "--sigma") p.sigmaModel = v;
        else if (k == "--stretch") p.stretch = v; else if (k == "--smoothing") p.smoothing = v;
        else if (k == "--budget") p.budget = static_cast<int>(v);
    }

    Trie trie;
    if (!trie.loadMmap((resources + "/fr_spellcheck.dict").c_str())) { std::fprintf(stderr, "cannot load dict\n"); return 1; }
    ProximityMap prox; installStaticProximity(prox);
    AccentCostTable accents; installAccents(accents);
    Scorer scorer; scorer.setProximityMap(&prox); scorer.setAccentCostTable(&accents);

    std::vector<Key> keys = renderedAzerty();
    SpatialModel spatial;
    {
        std::vector<uint16_t> c; std::vector<float> x, y;
        for (const Key& k : keys) if (k.ch != '\'') { c.push_back(k.ch); x.push_back(k.x); y.push_back(k.y); }
        spatial.setKeys(c.data(), x.data(), y.data(), c.size(), 1.0f, ROW_PITCH);
        spatial.setSigma(p.sigmaModel);
    }
    NextLetterModel next;
    auto tb = std::chrono::steady_clock::now();
    next.build(trie);
    double buildMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - tb).count();

    // Running-text sample: tokens drawn by corpus frequency.
    auto freq = readFrequency(resources + "/fr_frequency.json");
    std::vector<std::u16string> vocab; std::vector<double> w;
    for (auto& [word, count] : freq) {
        auto u = toU16(word);
        if (isTypable(u) && trie.wordExists(reinterpret_cast<const uint16_t*>(u.data()), u.size())) { vocab.push_back(u); w.push_back(count); }
    }
    std::mt19937 rng(42);
    std::discrete_distribution<size_t> pick(w.begin(), w.end());
    std::vector<std::u16string> running;
    for (int i = 0; i < n; i++) running.push_back(vocab[pick(rng)]);
    // Rare words: uniform over the bottom half of the list, length >= 5.
    std::vector<std::u16string> rare;
    {
        std::vector<size_t> idx(vocab.size()); for (size_t i = 0; i < idx.size(); i++) idx[i] = i;
        std::sort(idx.begin(), idx.end(), [&](size_t a, size_t b) { return w[a] > w[b]; });
        std::vector<std::u16string> pool;
        for (size_t i = idx.size() / 2; i < idx.size(); i++) if (vocab[idx[i]].size() >= 5) pool.push_back(vocab[idx[i]]);
        std::uniform_int_distribution<size_t> u(0, pool.size() - 1);
        for (int i = 0; i < n / 4; i++) rare.push_back(pool[u(rng)]);
    }
    // Words the dictionary does not know (names, English): the risk case for resizing.
    std::vector<std::u16string> unknown;
    {
        auto en = readFrequency(resources + "/en_frequency.json");
        std::vector<std::u16string> pool;
        for (auto& [word, count] : en) {
            auto u = toU16(word);
            if (u.size() >= 4 && isTypable(u) && !trie.wordExists(reinterpret_cast<const uint16_t*>(u.data()), u.size())) pool.push_back(u);
            if (pool.size() >= 20000) break;
        }
        std::uniform_int_distribution<size_t> u(0, pool.size() - 1);
        for (int i = 0; i < n / 4; i++) unknown.push_back(pool[u(rng)]);
    }

    std::printf("dictionary: %u words; next-letter table built in %.1f ms\n", trie.wordCount(), buildMs);
    std::printf("params: lambda %.2f, model sigma %.2f, stretch %.2f, smoothing %.2f, budget %d\n\n",
                p.lambda, p.sigmaModel, p.stretch, p.smoothing, p.budget);

    const Config configs[] = {
        {"A today (static proximity)", false, false},
        {"B + touch-aware correction", true, false},
        {"C + hidden key resizing", true, true},
        {"D resizing only", false, true},
    };
    for (float sigmaTrue : {0.20f, 0.30f, 0.40f}) {
        std::printf("== tap noise sigma %.2f key widths ==\n", sigmaTrue);
        std::printf("%-30s %10s %10s %10s %12s %12s\n", "pipeline", "running", "rare", "keys", "unknown keys", "us/correct");
        for (const Config& cfg : configs) {
            Outcome r = run(trie, scorer, spatial, next, keys, running, sigmaTrue, cfg, p, true, 7);
            Outcome rr = run(trie, scorer, spatial, next, keys, rare, sigmaTrue, cfg, p, true, 8);
            Outcome u = run(trie, scorer, spatial, next, keys, unknown, sigmaTrue, cfg, p, false, 9);
            std::printf("%-30s %9.2f%% %9.2f%% %9.2f%% %11.2f%% %12.1f",
                        cfg.name, 100.0 * r.wordsOk / r.words, 100.0 * rr.wordsOk / rr.words,
                        100.0 * r.keysOk / r.keys, 100.0 * u.keysOk / u.keys,
                        r.corrections ? r.correctUs / r.corrections : 0.0);
            if (r.resolves) std::printf("   resolve %.1f us", r.resolveUs / r.resolves);
            std::printf("\n");
        }
        std::printf("\n");
    }
    return 0;
}
