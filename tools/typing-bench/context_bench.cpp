// Context bench: imprecise taps on real French sentences, so the word before can help.
//
// bench.cpp scores isolated words. Here every word is typed inside its sentence, which
// lets three uses of the previous word be measured:
//   - the bigram rerank the keyboard shipped until this bench removed it
//     (TextPredictionEngine.spellCheck with previousWord), ported below;
//   - context-aware key resizing: the next-letter prior also counts the words the n-gram
//     model expects after the previous word;
//   - real-word correction: a slip that lands on another valid word ("se" for "de",
//     "me" for "le") is replaced when the tap was near the border AND the previous
//     word makes the neighbour much likelier.
//
// Sentences: Universal Dependencies French-GSD (CC BY-SA 4.0), read from the .conllu
// files at run time, never copied into the repository. See README.md.
#include "bench_common.h"
#include "ouispr_ngram.h"
#include "ouispr_spatial.h"
#include "ouispr_trie.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <random>

// --- Text helpers ---


static char16_t lowerU16(char16_t c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    if (c >= 0xC0 && c <= 0xDE && c != 0xD7) return c + 32;
    if (c == 0x152) return 0x153;
    return c;
}

static bool isLetter(char16_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 0xE0 && c <= 0xFF && c != 0xF7) || c == 0x153;
}

static const char16_t PROPER_MARK = 0x0001;

/// Words of a sentence, lowercased: runs of letters, an apostrophe kept inside a run
/// ("l'homme", "aujourd'hui"). Everything else separates.
static std::vector<std::u16string> tokenize(const std::string& line) {
    std::u16string s = toU16(line);
    std::vector<std::u16string> out;
    std::u16string cur;
    for (size_t i = 0; i < s.size(); i++) {
        char16_t c = lowerU16(s[i] == u'’' ? u'\'' : s[i]);
        // A capital inside the sentence starts a proper noun: the keyboard keeps an
        // unknown capitalised word as typed (ProperNounGuard), so it is marked and
        // left out of the score.
        if (isLetter(c) && cur.empty() && c != s[i] && !out.empty()) cur.push_back(PROPER_MARK);
        if (isLetter(c)) { cur.push_back(c); continue; }
        if (c == '\'' && !cur.empty() && i + 1 < s.size() && isLetter(lowerU16(s[i + 1]))) { cur.push_back(c); continue; }
        if (!cur.empty()) { out.push_back(cur); cur.clear(); }
    }
    if (!cur.empty()) out.push_back(cur);
    return out;
}

static std::vector<std::vector<std::u16string>> readConllu(const std::vector<std::string>& paths) {
    std::vector<std::vector<std::u16string>> out;
    for (const auto& p : paths) {
        std::ifstream f(p);
        std::string line;
        while (std::getline(f, line)) {
            const std::string tag = "# text = ";
            if (line.rfind(tag, 0) == 0) out.push_back(tokenize(line.substr(tag.size())));
        }
    }
    return out;
}


// --- Bench ---

struct Params {
    float lambda = 0.10f, sigmaModel = 0.30f, stretch = 0.25f, smoothing = 0.30f;
    int budget = 4000;
    float contextMix = 0.5f;   // share of the n-gram prior in the next-letter prior
    float logPerScore = 20.0f / 65535.0f;  // n-gram score unit -> natural log of a count
    float realWordMargin = 2.0f;  // nats the neighbour must win by
};

struct Config {
    const char* name;
    int rerank;           // shipped bigram rerank of non-words: 0 off, 1 full, 2 trie candidates only, 3 n-gram neighbours only
    bool contextKeys;     // n-gram prior in hidden key resizing
    bool realWord;        // real-word correction from tap + context
};

struct Outcome {
    int words = 0, ok = 0, oov = 0;
    int typedRight = 0, typedRightChanged = 0;  // false corrections
    int realWordSlips = 0, realWordFixed = 0;
    double us = 0; int calls = 0;
};

struct Engines {
    const Trie* trie; const Scorer* scorer; const SpatialModel* spatial;
    const NextLetterModel* next; const NgramEngine* ngrams; const std::vector<Key>* keys;
    // Words an exact typing is trusted for (kept without a look at their neighbours).
    // Null: every dictionary word is.
    const Trie* trusted = nullptr;
};

static bool exists(const Trie& t, const std::u16string& w) {
    return t.wordExists(reinterpret_cast<const uint16_t*>(w.data()), w.size());
}

/// Next-letter prior: the dictionary's, mixed with the continuations the n-gram model
/// lists after the previous word that start with the letters typed so far.
static bool contextWeights(const Engines& e, const std::u16string& prefix, const std::string& prev,
                           const Params& p, bool useContext, float* out) {
    bool ok = e.next->weights(*e.trie, reinterpret_cast<const uint16_t*>(prefix.data()), prefix.size(), p.budget, out);
    if (!useContext || prev.empty()) return ok;
    auto preds = e.ngrams->predictAfterWord(prev.c_str(), 16);
    std::vector<float> ctx(SUBSTITUTION_SLOT_COUNT, 0.0f);
    float ctxTotal = 0;
    for (const auto& r : preds) {
        std::u16string w = toU16(r.word);
        if (w.size() <= prefix.size() || w.compare(0, prefix.size(), prefix) != 0) continue;
        int slot = substitutionSlot(w[prefix.size()]);
        if (slot < 0) continue;
        float m = std::exp(r.score * p.logPerScore);
        ctx[slot] += m; ctxTotal += m;
    }
    if (ctxTotal <= 0) return ok;
    float dictTotal = 0;
    if (ok) for (int i = 0; i < SUBSTITUTION_SLOT_COUNT; i++) dictTotal += std::max(0.0f, out[i]);
    for (int i = 0; i < SUBSTITUTION_SLOT_COUNT; i++) {
        float d = dictTotal > 0 ? std::max(0.0f, out[i]) / dictTotal : 0.0f;
        out[i] = (dictTotal > 0 ? (1 - p.contextMix) * d : 0.0f) + p.contextMix * ctx[i] / ctxTotal;
    }
    return true;
}

/// The shipped rerank (TextPredictionEngine.spellCheck(_:previousWord:)), for a typed
/// non-word: trie candidates plus n-gram predictions at edit distance 1, reranked by
/// bigram score, never moving to a candidate farther than the trie's winner.
static std::u16string rerank(const Engines& e, const std::u16string& typed, const std::vector<Candidate>& cands,
                             const std::string& prev, int mode = 1) {
    std::u16string top = toU16(cands[0].word);
    if (prev.empty()) return top;
    std::vector<std::pair<std::u16string, uint16_t>> set;
    auto add = [&](const std::u16string& w, uint16_t s) {
        for (auto& [k, v] : set) if (k == w) { v = std::max(v, s); return; }
        set.emplace_back(w, s);
    };
    for (size_t i = 0; i < cands.size() && i < (mode == 3 ? 1u : 3u); i++) {
        std::u16string w = toU16(cands[i].word);
        add(w, e.ngrams->bigramScore(prev.c_str(), toU8(w).c_str()));
    }
    if (typed.size() >= 3 && mode != 2) {
        for (const auto& r : e.ngrams->predictAfterWord(prev.c_str(), 8)) {
            std::u16string w = toU16(r.word);
            if (editDistance(typed, w) != 1) continue;
            uint16_t s = e.ngrams->bigramScore(prev.c_str(), r.word.c_str());
            if (s > 0) add(w, s);
        }
    }
    bool evidence = false;
    for (auto& [k, v] : set) evidence = evidence || v > 0;
    if (!evidence) return top;
    int topED = editDistance(typed, top);
    std::u16string best = top; int bestScore = -1;
    for (auto& [k, v] : set) {
        if (editDistance(typed, k) > topED) continue;
        if (static_cast<int>(v) > bestScore) { bestScore = v; best = k; }
    }
    return best;
}

/// Real-word correction: `typed` is a valid word. A neighbour one substitution away
/// replaces it when log P(neighbour | prev) − log P(typed | prev) exceeds the extra
/// distance from the tap to the neighbour's key, plus a margin. The n-gram model only
/// lists 16 continuations per word: an unlisted word gets the 16th score minus 1 nat.
static std::u16string realWord(const Engines& e, const std::u16string& typed, const std::string& prev,
                               const std::vector<float>& tx, const std::vector<float>& ty,
                               const std::vector<bool>& hasTap, const Params& p) {
    if (prev.empty() || typed.size() < 2 || typed.find(u'\'') != std::u16string::npos) return typed;
    auto preds = e.ngrams->predictAfterWord(prev.c_str(), 16);
    if (preds.empty()) return typed;
    float floorLog = preds.back().score * p.logPerScore - 1.0f;
    auto logP = [&](const std::u16string& w) {
        uint16_t s = e.ngrams->bigramScore(prev.c_str(), toU8(w).c_str());
        return s > 0 ? s * p.logPerScore : floorLog;
    };
    float typedLog = logP(typed);
    const float twoSigma2 = 2 * p.sigmaModel * p.sigmaModel;
    std::u16string best = typed; float bestGain = p.realWordMargin;
    for (const auto& r : preds) {
        std::u16string w = toU16(r.word);
        if (w.size() != typed.size() || w == typed) continue;
        int pos = -1, diffs = 0;
        for (size_t i = 0; i < w.size(); i++) if (w[i] != typed[i]) { diffs++; pos = i; }
        if (diffs != 1 || !hasTap[pos]) continue;
        const Key* kt = nullptr; const Key* kw = nullptr;
        for (const Key& k : *e.keys) { if (k.ch == typed[pos]) kt = &k; if (k.ch == w[pos]) kw = &k; }
        if (!kt || !kw) continue;
        float dt = (tx[pos] - kt->x) * (tx[pos] - kt->x) + (ty[pos] - kt->y) * (ty[pos] - kt->y);
        float dw = (tx[pos] - kw->x) * (tx[pos] - kw->x) + (ty[pos] - kw->y) * (ty[pos] - kw->y);
        float gain = (r.score * p.logPerScore - typedLog) - (dw - dt) / twoSigma2;
        if (gain > bestGain) { bestGain = gain; best = w; }
    }
    return best;
}

static Outcome run(const Engines& e, const std::vector<std::vector<std::u16string>>& sentences,
                   float sigmaTrue, const Config& cfg, const Params& p, unsigned seed) {
    std::mt19937 rng(seed);
    std::normal_distribution<float> noise(0.0f, sigmaTrue);
    std::map<char16_t, const Key*> byChar;
    for (const Key& k : *e.keys) byChar[k.ch] = &k;
    Outcome o;
    std::vector<float> weights(SUBSTITUTION_SLOT_COUNT);
    for (const auto& sentence : sentences) {
        std::string prev;
        for (const auto& token : sentence) {
            if (!token.empty() && token[0] == PROPER_MARK) { prev = toU8(token.substr(1)); continue; }
            // The elided head ("l'", "qu'") is taken as typed right; the word after the
            // apostrophe is what the keyboard corrects.
            size_t apo = token.rfind(u'\'');
            std::u16string head = apo == std::u16string::npos ? u"" : token.substr(0, apo + 1);
            std::u16string target = apo == std::u16string::npos ? token : token.substr(apo + 1);
            if (!isTypable(target)) { prev = toU8(token); continue; }

            std::u16string typed;
            std::vector<float> tx, ty; std::vector<bool> hasTap;
            auto t0 = std::chrono::steady_clock::now();
            for (char16_t c : target) {
                if (baseOf(c) != c) { typed.push_back(c); tx.push_back(0); ty.push_back(0); hasTap.push_back(false); continue; }
                const Key* aim = byChar[c];
                float x = aim->x + noise(rng), y = aim->y + noise(rng);
                const Key& g = geometricKey(*e.keys, x, y);
                char16_t out = g.ch;
                if (g.ch != '\'' && contextWeights(e, typed, prev, p, cfg.contextKeys, weights.data()))
                    out = e.spatial->resolveTouch(x, y, g.ch, weights.data(), p.stretch, p.smoothing);
                typed.push_back(out); tx.push_back(x); ty.push_back(y); hasTap.push_back(true);
            }

            std::u16string final = typed;
            bool typedValid = exists(*e.trie, typed);
            bool trusted = typedValid && e.trie->wordIsTrusted(reinterpret_cast<const uint16_t*>(typed.data()), typed.size())
                           && (!e.trusted || exists(*e.trusted, typed));
            if (!trusted) {
                std::vector<float> costs(typed.size() * SUBSTITUTION_SLOT_COUNT, -1.0f);
                e.spatial->tapCosts(tx.data(), ty.data(), typed.size(), p.lambda, 0.0f, costs.data());
                for (size_t i = 0; i < typed.size(); i++)
                    if (!hasTap[i]) std::fill(costs.begin() + i * SUBSTITUTION_SLOT_COUNT, costs.begin() + (i + 1) * SUBSTITUTION_SLOT_COUNT, -1.0f);
                auto cands = e.scorer->correct(*e.trie, reinterpret_cast<const uint16_t*>(typed.data()), typed.size(), 2.0f, 5, costs.data());
                if (typedValid && keepsWeakWord(cands, typed)) final = typed;
                else if (!cands.empty()) final = cfg.rerank ? rerank(e, typed, cands, prev, cfg.rerank) : pickCorrection(*e.trie, cands, typed);
            } else if (cfg.realWord) {
                final = realWord(e, typed, prev, tx, ty, hasTap, p);
            }
            o.us += std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t0).count();
            o.calls++;

            o.words++;
            if (!exists(*e.trie, target)) o.oov++;
            if (final == target) o.ok++;
            if (typed == target) { o.typedRight++; if (final != target) o.typedRightChanged++; }
            if (typed != target && typedValid) { o.realWordSlips++; if (final == target) o.realWordFixed++; }
            prev = toU8(head + final);
        }
    }
    return o;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: context-bench <Resources dir> <file.conllu>... [--key value]\n");
        return 1;
    }
    std::string resources = argv[1];
    std::vector<std::string> files;
    std::string trustedPath;
    Params p;
    for (int i = 2; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--trusted" && i + 1 < argc) { trustedPath = argv[++i]; continue; }
        if (a.rfind("--", 0) == 0 && i + 1 < argc) {
            float v = std::atof(argv[++i]);
            if (a == "--mix") p.contextMix = v; else if (a == "--logmax") p.logPerScore = v / 65535.0f;
            else if (a == "--margin") p.realWordMargin = v; else if (a == "--weakmargin") gWeakMargin = v; else if (a == "--weakpick") gWeakPick = static_cast<int>(v); else if (a == "--weakpickmargin") gWeakPickMargin = v; else if (a == "--stretch") p.stretch = v;
            continue;
        }
        files.push_back(a);
    }

    Trie trie;
    if (!trie.loadMmap((resources + "/fr_spellcheck.dict").c_str())) { std::fprintf(stderr, "cannot load dict\n"); return 1; }
    NgramEngine ngrams;
    if (!ngrams.load((resources + "/fr_ngrams.dict").c_str())) { std::fprintf(stderr, "cannot load ngrams\n"); return 1; }
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
    NextLetterModel next; next.build(trie);
    Engines e{&trie, &scorer, &spatial, &next, &ngrams, &keys};
    Trie trustedTrie;
    if (!trustedPath.empty()) {
        if (!trustedTrie.loadMmap(trustedPath.c_str())) { std::fprintf(stderr, "cannot load trusted dict\n"); return 1; }
        e.trusted = &trustedTrie;
    }

    auto sentences = readConllu(files);
    size_t tokens = 0; for (auto& s : sentences) tokens += s.size();
    std::printf("%zu sentences, %zu words; dictionary %u words\n", sentences.size(), tokens, trie.wordCount());
    std::printf("params: mix %.2f, logmax %.1f, margin %.1f, stretch %.2f\n\n",
                p.contextMix, p.logPerScore * 65535.0f, p.realWordMargin, p.stretch);

    const Config configs[] = {
        {"A PR 19, no context", 0, false, false},
        {"B PR 19 + shipped rerank", 1, false, false},
        {"B2 rerank trie cands only", 2, false, false},
        {"B3 n-gram neighbours only", 3, false, false},
        {"C A + context keys", 0, true, false},
        {"D C + real-word fix", 0, true, true},
    };
    for (float sigma : {0.20f, 0.30f, 0.40f}) {
        std::printf("== tap noise sigma %.2f ==\n", sigma);
        std::printf("%-28s %8s %9s %12s %14s %8s\n", "pipeline", "right", "not in dict", "false fixes", "real-word fixed", "us/word");
        for (const Config& cfg : configs) {
            Outcome o = run(e, sentences, sigma, cfg, p, 11);
            std::printf("%-28s %7.2f%% %8.2f%% %11.3f%% %8d/%-6d %8.1f\n", cfg.name,
                        100.0 * o.ok / o.words, 100.0 * o.oov / o.words,
                        100.0 * o.typedRightChanged / std::max(1, o.typedRight),
                        o.realWordFixed, o.realWordSlips, o.us / std::max(1, o.calls));
        }
        std::printf("\n");
    }
    return 0;
}
