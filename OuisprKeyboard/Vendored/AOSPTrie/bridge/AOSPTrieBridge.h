// AOSP-inspired trie engine for Ouispr. Apache 2.0.
// ObjC bridge header -- exposes C++ trie engine to Swift via bridging header.
// No C++ types leak into this header so it can be imported from Swift.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result from spell check. nil means word is correctly spelled.
@interface AOSPTrieResult : NSObject
@property (nonatomic, copy) NSString *correction;
@property (nonatomic, copy) NSArray<NSString *> *alternatives;
@property (nonatomic) float score;
@end

@interface AOSPTrieBridge : NSObject

- (BOOL)loadDictionaryAtPath:(NSString *)path;
- (void)unloadDictionary;
- (BOOL)isLoaded;

/// Returns nil if word is correctly spelled or not found.
/// Returns AOSPTrieResult with best correction, up to 2 alternatives, and score.
- (nullable AOSPTrieResult *)spellCheck:(NSString *)word maxEditDistance:(float)maxDist;

/// Returns nearby words (edit distance candidates) excluding the input word itself.
/// Unlike spellCheck, this does NOT return nil for correctly-spelled words.
/// Used by n-gram context boosting to find alternatives for valid-but-rare words.
- (NSArray<NSString *> *)nearbyWords:(NSString *)word maxEditDistance:(float)maxDist maxResults:(NSUInteger)maxResults;

/// Check if word exists in dictionary.
- (BOOL)wordExists:(NSString *)word;

/// Get frequency of word (0 if not found).
- (NSInteger)getFrequency:(NSString *)word;

/// Word count from the loaded dictionary header.
- (NSUInteger)wordCount;

/// Install the proximity cost table for the active keyboard layout.
///
/// The table is computed by OuisprCore's `KeyboardProximity`, which owns the key geometry
/// of every layout: the keyboard target has no test bundle, so a table declared here could
/// not be pinned by anything (#321). Pass `ProximityCostTable.charactersData` (UTF-16 code
/// units, one per key) and `.distancesData` (count x count floats, row-major).
/// Returns NO if the two buffers disagree on size; the previous table then stays installed.
- (BOOL)setProximityTableWithCharacters:(NSData *)characters distances:(NSData *)distances
    NS_SWIFT_NAME(setProximityTable(characters:distances:));

/// Install the accent substitution costs.
///
/// Computed by OuisprCore's `AccentRelation`, for the same reason. Pass
/// `AccentCostPairs.fromData` / `.toData` (UTF-16 code units) and `.costsData` (floats),
/// three parallel buffers of equal length.
/// Returns NO if the buffers disagree on size; the previous table then stays installed.
- (BOOL)setAccentCostsFrom:(NSData *)from to:(NSData *)to costs:(NSData *)costs
    NS_SWIFT_NAME(setAccentCosts(from:to:costs:));

// --- Touch-aware typing (spatial model) ---

/// Install the letter keys as rendered, for touch-aware correction and hidden key resizing.
///
/// Coordinates are in key widths on both axes (divide points by one key's pitch), measured
/// on the keyboard actually on screen. `characters` holds UTF-16 code units, `centerX` and
/// `centerY` one float each per key. Returns NO if the buffers disagree on size; the
/// previous keys then stay installed.
- (BOOL)setSpatialKeysWithCharacters:(NSData *)characters
                             centerX:(NSData *)centerX
                             centerY:(NSData *)centerY
                            keyWidth:(float)keyWidth
                           keyHeight:(float)keyHeight
    NS_SWIFT_NAME(setSpatialKeys(characters:centerX:centerY:keyWidth:keyHeight:));

/// Which letter a touch most probably meant, given the letters already typed in the word.
/// Only border touches can move to a neighbour (see ouispr_spatial.h). Returns
/// `geometricKey` unchanged when no dictionary or keys are loaded.
- (unichar)resolveTouchAtX:(float)x y:(float)y
              geometricKey:(unichar)geometricKey
               afterPrefix:(NSString *)prefix
    NS_SWIFT_NAME(resolveTouch(x:y:geometricKey:prefix:));

/// `spellCheck:maxEditDistance:` priced from where each letter was tapped.
/// `tapX` / `tapY` hold one float per UTF-16 code unit of `word`, in the coordinates of
/// `setSpatialKeys`; NaN marks a letter with no tap (pasted, long-pressed). Falls back to
/// the plain spell check if the buffers do not match the word.
- (nullable AOSPTrieResult *)spellCheck:(NSString *)word
                        maxEditDistance:(float)maxDist
                                   tapX:(NSData *)tapX
                                   tapY:(NSData *)tapY
    NS_SWIFT_NAME(spellCheck(_:maxEditDistance:tapX:tapY:));

// --- N-gram prediction methods ---

/// Load n-gram binary file for next-word prediction.
- (BOOL)loadNgramsAtPath:(NSString *)path;

/// Unload n-gram data and release mmap'd memory.
- (void)unloadNgrams;

/// Whether n-gram data is loaded and ready for predictions.
- (BOOL)ngramsLoaded;

/// Predict top-N next words given one previous word (bigram lookup).
/// Returns array of NSString, sorted by score descending.
- (NSArray<NSString *> *)predictAfterWord:(NSString *)word maxResults:(NSUInteger)max;

/// Predict top-N next words given two previous words (trigram + bigram backoff).
/// Returns array of NSString, sorted by score descending.
- (NSArray<NSString *> *)predictAfterWord1:(NSString *)word1 word2:(NSString *)word2 maxResults:(NSUInteger)max;

/// Get bigram score for a specific word following a previous word (for correction boosting).
/// Returns 0 if no n-gram match found.
- (uint16_t)bigramScoreForWord:(NSString *)word afterWord:(NSString *)prevWord;

@end

NS_ASSUME_NONNULL_END
