// AOSP-inspired trie engine for Ouispr. Apache 2.0.
// ObjC++ implementation -- bridges C++ trie engine to ObjC for Swift interop.

#import "AOSPTrieBridge.h"

#include "ouispr_trie.h"
#include "ouispr_scorer.h"
#include "ouispr_proximity.h"
#include "ouispr_ngram.h"
#include "ouispr_spatial.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include <vector>

// ---------- AOSPTrieResult ----------

@implementation AOSPTrieResult
@end

// ---------- AOSPTrieBridge ----------

@implementation AOSPTrieBridge {
    ouispr::Trie _trie;
    ouispr::Scorer _scorer;
    ouispr::ProximityMap _proximityMap;
    ouispr::AccentCostTable _accentCosts;
    BOOL _loaded;
    ouispr::NgramEngine* _ngramEngine;
    ouispr::SpatialModel _spatial;
    ouispr::NextLetterModel _nextLetters;
}

// Spatial parameters, tuned on tools/typing-bench (see its README for the numbers).
// lambda: how strongly a tap's distance to a key turns into edit cost.
static constexpr float kTapCostLambda = 0.10f;
// sigma: assumed spread of a touch around the aimed key centre, in key widths.
static constexpr float kTouchSigma = 0.30f;
// The most a key can grow, invisibly, on each side: a quarter of a key width.
static constexpr float kMaxKeyStretch = 0.25f;
// Share of a uniform prior mixed into the next-letter prediction, so rare letters and
// words the dictionary does not know stay reachable from a border tap.
static constexpr float kNextLetterSmoothing = 0.30f;
// Trie nodes walked for an exact next-letter prediction before the letter-bigram fallback.
static constexpr int kNextLetterNodeBudget = 4000;
// Share of the n-gram continuations after the previous word in the next-letter prior,
// and the n-gram score unit as a natural log of a count. Measured on
// tools/typing-bench/context_bench.cpp (36,922 words of French sentences): +0.05 /
// +0.45 / +0.72 pt of words right at tap noise 0.20 / 0.30 / 0.40.
static constexpr float kContextMix = 0.5f;
static constexpr float kNgramLogPerScore = 20.0f / 65535.0f;
static constexpr size_t kContextPredictions = 16;
// How much better than a weak word typed exactly a candidate must score to replace it
// (French long-tail vocabulary, see Trie::wordIsTrusted). 1.5 kept every gain of the
// larger dictionary on real sentences and cost < 0.1 pt on isolated common words.
static constexpr float kWeakWordMargin = 1.5f;

- (instancetype)init {
    self = [super init];
    if (self) {
        _loaded = NO;
        _ngramEngine = new ouispr::NgramEngine();
        _spatial.setSigma(kTouchSigma);
        // Both tables are members with a stable address, so the scorer is wired to them
        // once here. Until OuisprCore installs their contents they are neutral: every
        // substitution costs 1.0 and no accent pair is related, which degrades to plain
        // edit distance rather than to wrong scores.
        _scorer.setProximityMap(&_proximityMap);
        _scorer.setAccentCostTable(&_accentCosts);
    }
    return self;
}

- (void)dealloc {
    _trie.unload();
    delete _ngramEngine;
}

- (BOOL)loadDictionaryAtPath:(NSString *)path {
    _trie.unload();
    _loaded = NO;

    bool success = _trie.loadMmap([path UTF8String]);
    if (success) {
        // Rebuilt per dictionary: the table describes one language. Built aside (~10 ms)
        // then copied in, so a touch on the main thread never sees a freed table; at worst
        // it reads a mix of two languages' floats for one keystroke.
        ouispr::NextLetterModel next;
        next.build(_trie);
        _nextLetters = next;
        _loaded = YES;
    }
    return success ? YES : NO;
}

- (void)unloadDictionary {
    _trie.unload();
    _loaded = NO;
}

- (BOOL)isLoaded {
    return _loaded;
}

/// Helper: convert NSString to uint16_t buffer.
/// Returns the number of UTF-16 code units written.
static int convertString(NSString *str, uint16_t *buffer, int bufferSize) {
    NSUInteger len = [str length];
    if ((int)len > bufferSize) len = bufferSize;
    [str getCharacters:buffer range:NSMakeRange(0, len)];
    return (int)len;
}

- (nullable AOSPTrieResult *)spellCheck:(NSString *)word maxEditDistance:(float)maxDist {
    if (!_loaded || [word length] == 0) return nil;

    // Convert input word to UTF-16 buffer
    uint16_t inputBuf[256];
    int inputLen = convertString(word, inputBuf, 256);
    if (inputLen == 0) return nil;

    // Run correction
    std::vector<ouispr::Candidate> candidates = _scorer.correct(
        _trie, inputBuf, inputLen, maxDist, 5
    );

    if (candidates.empty()) return nil;

    // Check if first result matches the input (word is correct)
    NSString *firstWord = [NSString stringWithUTF8String:candidates[0].word];
    if ([firstWord isEqualToString:word]) return nil;
    if ([self keepsWeakWord:word buffer:inputBuf length:inputLen candidates:candidates]) return nil;

    // Build result
    AOSPTrieResult *result = [[AOSPTrieResult alloc] init];
    result.correction = firstWord;
    result.score = candidates[0].score;

    NSMutableArray<NSString *> *alts = [NSMutableArray array];
    for (size_t i = 1; i < candidates.size() && i <= 2; i++) {
        NSString *alt = [NSString stringWithUTF8String:candidates[i].word];
        [alts addObject:alt];
    }
    result.alternatives = [alts copy];

    return result;
}

/// A weak dictionary word typed exactly (see `wordIsTrusted:`) stays unless the best
/// candidate outscores it by kWeakWordMargin. Words that are not weak: always NO.
- (BOOL)keepsWeakWord:(NSString *)word
               buffer:(const uint16_t *)buffer
               length:(int)length
           candidates:(const std::vector<ouispr::Candidate> &)candidates {
    if (!_trie.wordExists(buffer, length) || _trie.wordIsTrusted(buffer, length)) return NO;
    const char *utf8 = [word UTF8String];
    float exact = 0.0f;
    for (const auto &c : candidates) {
        if (std::strcmp(c.word, utf8) == 0) exact = std::max(exact, c.score);
    }
    return candidates[0].score <= kWeakWordMargin * exact;
}

- (NSArray<NSString *> *)nearbyWords:(NSString *)word maxEditDistance:(float)maxDist maxResults:(NSUInteger)maxResults {
    if (!_loaded || [word length] == 0) return @[];

    uint16_t inputBuf[256];
    int inputLen = convertString(word, inputBuf, 256);
    if (inputLen == 0) return @[];

    std::vector<ouispr::Candidate> candidates = _scorer.correct(
        _trie, inputBuf, inputLen, maxDist, (int)maxResults + 1
    );

    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:candidates.size()];
    for (const auto& c : candidates) {
        NSString *w = [NSString stringWithUTF8String:c.word];
        // Skip exact match — caller already knows the input word
        if (![w isEqualToString:word]) {
            [result addObject:w];
        }
        if ([result count] >= maxResults) break;
    }
    return [result copy];
}

- (BOOL)wordExists:(NSString *)word {
    if (!_loaded || [word length] == 0) return NO;

    uint16_t buf[256];
    int len = convertString(word, buf, 256);
    return _trie.wordExists(buf, len) ? YES : NO;
}

- (BOOL)wordIsTrusted:(NSString *)word {
    if (!_loaded || [word length] == 0) return NO;

    uint16_t buf[256];
    int len = convertString(word, buf, 256);
    return _trie.wordIsTrusted(buf, len) ? YES : NO;
}

- (NSInteger)getFrequency:(NSString *)word {
    if (!_loaded || [word length] == 0) return 0;

    uint16_t buf[256];
    int len = convertString(word, buf, 256);
    return (NSInteger)_trie.getFrequency(buf, len);
}

- (NSUInteger)wordCount {
    if (!_loaded) return 0;
    return (NSUInteger)_trie.wordCount();
}

- (BOOL)setProximityTableWithCharacters:(NSData *)characters distances:(NSData *)distances {
    NSUInteger count = characters.length / sizeof(uint16_t);
    if (count == 0 || distances.length != count * count * sizeof(float)) return NO;

    return _proximityMap.setTable(static_cast<const uint16_t *>(characters.bytes),
                                  (int)count,
                                  static_cast<const float *>(distances.bytes)) ? YES : NO;
}

- (BOOL)setAccentCostsFrom:(NSData *)from to:(NSData *)to costs:(NSData *)costs {
    NSUInteger count = from.length / sizeof(uint16_t);
    if (count == 0 || to.length != from.length || costs.length != count * sizeof(float)) return NO;

    return _accentCosts.setPairs(static_cast<const uint16_t *>(from.bytes),
                                 static_cast<const uint16_t *>(to.bytes),
                                 static_cast<const float *>(costs.bytes),
                                 (int)count) ? YES : NO;
}

// --- Touch-aware typing (spatial model) ---

- (BOOL)setSpatialKeysWithCharacters:(NSData *)characters
                             centerX:(NSData *)centerX
                             centerY:(NSData *)centerY
                            keyWidth:(float)keyWidth
                           keyHeight:(float)keyHeight {
    NSUInteger count = characters.length / sizeof(uint16_t);
    if (count == 0 || centerX.length != count * sizeof(float) || centerY.length != count * sizeof(float)) {
        return NO;
    }
    return _spatial.setKeys(static_cast<const uint16_t *>(characters.bytes),
                            static_cast<const float *>(centerX.bytes),
                            static_cast<const float *>(centerY.bytes),
                            (int)count, keyWidth, keyHeight) ? YES : NO;
}

- (unichar)resolveTouchAtX:(float)x y:(float)y
              geometricKey:(unichar)geometricKey
               afterPrefix:(NSString *)prefix
              previousWord:(nullable NSString *)previousWord {
    if (!_loaded || !_spatial.hasKeys() || !_nextLetters.isBuilt()) return geometricKey;

    uint16_t prefixBuf[128];
    int prefixLen = convertString(prefix, prefixBuf, 128);
    float weights[ouispr::SUBSTITUTION_SLOT_COUNT];
    bool hasPrior = _nextLetters.weights(_trie, prefixBuf, prefixLen, kNextLetterNodeBudget, weights);
    if ([self mixContextAfter:previousWord prefix:prefixBuf length:prefixLen hasPrior:hasPrior into:weights]) {
        hasPrior = true;
    }
    if (!hasPrior) return geometricKey;
    return _spatial.resolveTouch(x, y, geometricKey, weights, kMaxKeyStretch, kNextLetterSmoothing);
}

/// Mixes into `weights` the next letters of the words the n-gram model expects after
/// `previousWord` that start with the typed prefix: (1 − kContextMix) of the dictionary's
/// prior plus kContextMix of the context's. NO when there is no such continuation.
- (BOOL)mixContextAfter:(nullable NSString *)previousWord
                 prefix:(const uint16_t *)prefix
                 length:(int)prefixLen
               hasPrior:(bool)hasPrior
                   into:(float *)weights {
    if ([previousWord length] == 0 || !_ngramEngine->isLoaded()) return NO;
    auto predictions = _ngramEngine->predictAfterWord([previousWord UTF8String], kContextPredictions);
    float context[ouispr::SUBSTITUTION_SLOT_COUNT] = {};
    float contextTotal = 0.0f;
    for (const auto& prediction : predictions) {
        NSString *word = [NSString stringWithUTF8String:prediction.word.c_str()];
        uint16_t buffer[128];
        int length = convertString(word, buffer, 128);
        if (length <= prefixLen || !std::equal(prefix, prefix + prefixLen, buffer)) continue;
        int slot = ouispr::substitutionSlot(buffer[prefixLen]);
        if (slot < 0) continue;
        float mass = std::exp(prediction.score * kNgramLogPerScore);
        context[slot] += mass;
        contextTotal += mass;
    }
    if (contextTotal <= 0.0f) return NO;
    float dictionaryTotal = 0.0f;
    if (hasPrior) {
        for (int i = 0; i < ouispr::SUBSTITUTION_SLOT_COUNT; i++) dictionaryTotal += std::max(0.0f, weights[i]);
    }
    for (int i = 0; i < ouispr::SUBSTITUTION_SLOT_COUNT; i++) {
        float dictionary = dictionaryTotal > 0.0f ? (1.0f - kContextMix) * std::max(0.0f, weights[i]) / dictionaryTotal : 0.0f;
        weights[i] = dictionary + kContextMix * context[i] / contextTotal;
    }
    return YES;
}

- (nullable AOSPTrieResult *)spellCheck:(NSString *)word
                        maxEditDistance:(float)maxDist
                                   tapX:(NSData *)tapX
                                   tapY:(NSData *)tapY {
    NSUInteger len = [word length];
    if (!_loaded || len == 0 || len > 128 || !_spatial.hasKeys()
        || tapX.length != len * sizeof(float) || tapY.length != len * sizeof(float)) {
        return [self spellCheck:word maxEditDistance:maxDist];
    }

    uint16_t inputBuf[128];
    int inputLen = convertString(word, inputBuf, 128);
    const float *xs = static_cast<const float *>(tapX.bytes);
    const float *ys = static_cast<const float *>(tapY.bytes);

    std::vector<float> costs(inputLen * ouispr::SUBSTITUTION_SLOT_COUNT, -1.0f);
    _spatial.tapCosts(xs, ys, inputLen, kTapCostLambda, 0.0f, costs.data());
    // Letters with no tap say nothing: the proximity map prices them, as before.
    for (int i = 0; i < inputLen; i++) {
        if (std::isnan(xs[i]) || std::isnan(ys[i])) {
            std::fill(costs.begin() + i * ouispr::SUBSTITUTION_SLOT_COUNT,
                      costs.begin() + (i + 1) * ouispr::SUBSTITUTION_SLOT_COUNT, -1.0f);
        }
    }

    std::vector<ouispr::Candidate> candidates = _scorer.correct(
        _trie, inputBuf, inputLen, maxDist, 5, costs.data()
    );
    if (candidates.empty()) return nil;

    NSString *firstWord = [NSString stringWithUTF8String:candidates[0].word];
    if ([firstWord isEqualToString:word]) return nil;
    if ([self keepsWeakWord:word buffer:inputBuf length:inputLen candidates:candidates]) return nil;

    AOSPTrieResult *result = [[AOSPTrieResult alloc] init];
    result.correction = firstWord;
    result.score = candidates[0].score;
    NSMutableArray<NSString *> *alts = [NSMutableArray array];
    for (size_t i = 1; i < candidates.size() && i <= 2; i++) {
        [alts addObject:[NSString stringWithUTF8String:candidates[i].word]];
    }
    result.alternatives = [alts copy];
    return result;
}

// --- N-gram prediction methods ---

- (BOOL)loadNgramsAtPath:(NSString *)path {
    _ngramEngine->unload();
    return _ngramEngine->load([path UTF8String]) ? YES : NO;
}

- (void)unloadNgrams {
    _ngramEngine->unload();
}

- (BOOL)ngramsLoaded {
    return _ngramEngine->isLoaded() ? YES : NO;
}

- (NSArray<NSString *> *)predictAfterWord:(NSString *)word maxResults:(NSUInteger)max {
    if (!_ngramEngine->isLoaded() || [word length] == 0) return @[];

    auto results = _ngramEngine->predictAfterWord([word UTF8String], (size_t)max);

    NSMutableArray<NSString *> *predictions = [NSMutableArray arrayWithCapacity:results.size()];
    for (const auto& r : results) {
        [predictions addObject:[NSString stringWithUTF8String:r.word.c_str()]];
    }
    return [predictions copy];
}

- (NSArray<NSString *> *)predictAfterWord1:(NSString *)word1 word2:(NSString *)word2 maxResults:(NSUInteger)max {
    if (!_ngramEngine->isLoaded() || [word1 length] == 0 || [word2 length] == 0) return @[];

    auto results = _ngramEngine->predictAfterWords(
        [word1 UTF8String], [word2 UTF8String], (size_t)max
    );

    NSMutableArray<NSString *> *predictions = [NSMutableArray arrayWithCapacity:results.size()];
    for (const auto& r : results) {
        [predictions addObject:[NSString stringWithUTF8String:r.word.c_str()]];
    }
    return [predictions copy];
}

- (uint16_t)bigramScoreForWord:(NSString *)word afterWord:(NSString *)prevWord {
    if (!_ngramEngine->isLoaded() || [word length] == 0 || [prevWord length] == 0) return 0;
    return _ngramEngine->bigramScore([prevWord UTF8String], [word UTF8String]);
}

@end
