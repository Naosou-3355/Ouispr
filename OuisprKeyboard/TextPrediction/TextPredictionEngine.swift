// OuisprKeyboard/TextPrediction/TextPredictionEngine.swift
// Core prediction logic: word completions, spell-checking, and accent suggestions.
import UIKit
import OuisprCore

/// Provides word completions, spell-checking, and accent suggestions for the keyboard.
///
/// WHY a class (not struct):
/// UITextChecker is a reference type (NSObject subclass) and maintains internal state
/// for its learned words dictionary. Using a class avoids copy-on-write issues and
/// ensures a single UITextChecker instance is reused throughout the keyboard session.
///
/// WHY UITextChecker:
/// Apple's built-in spell checker and word completion engine. It uses the system
/// dictionary which is already installed on every iOS device -- no additional data
/// download needed. We combine its completions with our FrequencyDictionary to
/// rank results by word frequency (most common words first).
class TextPredictionEngine {

    /// Shared instance — engines are heavy (~3 MiB FrequencyDictionary + AOSP trie mmap).
    /// Per-controller instances were leaking via SwiftUI @ObservedObject zombies that
    /// survive their owning KeyboardViewController.deinit (KeyboardRootView struct held
    /// alive by KeyboardState.shared.objectWillChange subscription). Sharing the heavy
    /// resources means the leak no longer multiplies memory per app-switch cycle.
    static let shared = TextPredictionEngine()

    private let textChecker = UITextChecker()
    private var frequencyDict = FrequencyDictionary()
    private let aospTrieEngine = AOSPTrieEngine()
    private var language: String = "fr"

    /// The active language's data profile, or nil if `language` is not a registered
    /// `SupportedLanguage`. Used to gate language-specific pipeline stages by
    /// reading profile data instead of hardcoded language string comparisons.
    private var profile: LanguageProfile? {
        SupportedLanguage(rawValue: language)?.profile
    }

    /// Whether this process has already reported that the prune was done in an
    /// earlier session. See `reportPruneAlreadyDone()`.
    private var hasReportedPruneAlreadyDone = false

    /// Contact names and text replacements (#873). Written on the main thread
    /// when the keyboard appears, read by `spellCheck` on the main thread (space)
    /// and on the suggestion queue (bar), hence the lock.
    private var supplementaryLexicon = SupplementaryLexicon.empty
    private let lexiconLock = NSLock()

    private init() {
        loadDictionaries(for: language)
    }

    /// Updates the active language for completions and spell-checking.
    /// Reloads the frequency dictionary for the new language.
    ///
    /// WHY reload on language change:
    /// We only keep one language's frequency data in memory at a time
    /// to stay within the keyboard extension's ~50MB memory budget.
    func setLanguage(_ lang: String) {
        language = lang
        loadDictionaries(for: lang)
    }

    /// Replaces the contacts + text replacements lexicon (#873).
    func setSupplementaryLexicon(_ lexicon: SupplementaryLexicon) {
        lexiconLock.lock()
        supplementaryLexicon = lexicon
        lexiconLock.unlock()
    }

    // MARK: - Touch-aware typing (SpatialTyping)

    /// Install the rendered letter keys, in key-width units.
    func setSpatialKeys(characters: [UInt16], centerX: [Float], centerY: [Float],
                        keyWidth: Float, keyHeight: Float) {
        aospTrieEngine.setSpatialKeys(
            characters: characters, centerX: centerX, centerY: centerY,
            keyWidth: keyWidth, keyHeight: keyHeight
        )
    }

    /// The letter a touch most probably meant after `prefix` (UTF-16 code unit).
    func resolveTouch(x: Float, y: Float, geometricKey: UInt16, prefix: String) -> UInt16 {
        aospTrieEngine.resolveTouch(x: x, y: y, geometricKey: geometricKey, prefix: prefix)
    }

    /// The lexicon's verdict on `word`, or nil when the lexicon does not know it.
    func lexiconDecision(for word: String) -> SupplementaryLexicon.Decision? {
        lexiconLock.lock()
        let lexicon = supplementaryLexicon
        lexiconLock.unlock()
        return lexicon.decision(for: word, isDictionaryWord: aospTrieEngine.wordExists(word.lowercased()))
    }

    /// Turns a lexicon verdict into a `spellCheck` result: nil keeps the word.
    private func lexiconResult(
        _ decision: SupplementaryLexicon.Decision,
        for word: String
    ) -> (correction: String, alternatives: [String])? {
        switch decision {
        case .keep:
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "lexicon")
            #endif
            return nil
        case .replace(let text):
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: text, branch: "lexicon", prevWord: nil
            )
            #endif
            return (text, [])
        }
    }

    /// Loads both dictionaries for `lang` and runs the work that can only happen
    /// once a dictionary is actually loaded.
    private func loadDictionaries(for lang: String) {
        // Verify language is available in UITextChecker
        let available = UITextChecker.availableLanguages
        if !available.contains(where: { $0.hasPrefix(lang) }) {
            print("[TextPredictionEngine] Warning: '\(lang)' not in available languages: \(available)")
        }
        frequencyDict.load(language: lang)
        aospTrieEngine.load(language: lang) { [weak self] _ in
            // The user dictionary's one-shot prune (#287). This is the first
            // moment in a cold session at which anything can ask the dictionary a
            // question, so it has to be one of the triggers — but it is not a
            // privileged one. A completion can belong to a load that has since
            // been superseded, and the trie it finds may be another language's
            // entirely; the gate below is what decides, not the fact of being
            // called from here.
            self?.pruneUserDictionaryIfPossible(trigger: "dictionary-loaded")
        }
    }

    /// Attempts the user dictionary's one-shot prune, and says so when it cannot.
    ///
    /// WHY there are several triggers and no privileged one (#287). Two triggers
    /// exist because neither is sufficient alone: the load completion is the only
    /// moment a cold session can ask the dictionary anything, and it is
    /// systematically starved once a session is warm — `viewWillAppear` issues a
    /// load on every keyboard appearance, each tearing the mmap down
    /// synchronously on the main thread before the previous completion, posted
    /// with `DispatchQueue.main.async`, gets to run. That starvation is why the
    /// prune never once ran on device. `viewWillAppear` therefore also attempts
    /// it *before* asking for the next load, while the previous dictionary is
    /// still mounted.
    ///
    /// Neither is trusted, and that is the point. `UserDictionaryPruneGate` holds
    /// the one precondition — the mounted dictionary is the active language's —
    /// so a trigger cannot be wrong, only early. Adding another is safe.
    ///
    /// Whenever the prune is still owed and cannot be done, a probe says why, so
    /// an export can never again be ambiguous between "never called", "called and
    /// declined", and "done long ago".
    func pruneUserDictionaryIfPossible(trigger: String) {
        let decision = UserDictionaryPruneGate.decide(
            alreadyPruned: UserDictionary.shared.hasPrunedTrieDuplicates,
            mountedLanguage: aospTrieEngine.mountedLanguage,
            activeLanguage: SupportedLanguage.active.rawValue
        )
        switch decision {
        case .run:
            UserDictionary.shared.pruneTrieDuplicatesIfNeeded(using: aospTrieEngine)
        case .alreadyDone:
            reportPruneAlreadyDone()
        case .notMounted, .languageMismatch:
            PersistentLog.log(.diagnosticProbe(
                component: "UserDictionaryPrune",
                instanceID: "",
                action: "skipped",
                details: "trigger=\(trigger) reason=\(decision.reason)"
            ))
        }
    }

    /// Says, once per keyboard process, that the prune has already been done.
    ///
    /// WHY this line has to exist. `userDictionaryPruned` is written once in the
    /// life of an install, and `PersistentLog` is a 1 MB file trimmed from the
    /// head — so an hour of ordinary use scrolls that line out of every later
    /// export. Without a standing statement, "this install was cleaned long ago"
    /// and "the prune is broken and never ran" are the same observation: silence.
    /// The third device pass on #287 was spent on exactly that ambiguity.
    ///
    /// WHY once per process and not once per call: `viewWillAppear` runs on every
    /// keyboard appearance, seventeen times in an hour of real use, and iOS keeps
    /// several controllers alive. One line per process is enough to date the
    /// state, and anything finer is the noise #255 was about.
    private func reportPruneAlreadyDone() {
        guard !hasReportedPruneAlreadyDone else { return }
        hasReportedPruneAlreadyDone = true
        PersistentLog.log(.diagnosticProbe(
            component: "UserDictionaryPrune",
            instanceID: "",
            action: "alreadyDone",
            details: "learnedCount=\(UserDictionary.shared.count)"
        ))
    }

    /// Whether `word` is genuinely new to the active language's dictionary —
    /// the gate the word-boundary learning site needs (#287 decision 2).
    ///
    /// WHY false while the dictionary is still loading: the answer would be
    /// "unknown" for every word typed in that window, and learning them all is
    /// exactly the pollution this gate exists to stop. AOSP LatinIME takes the
    /// same position for the same reason — it turns learning off entirely on a
    /// slow InputConnection, because a word it cannot vet is a word it should
    /// not keep. If we cannot ask, we do not learn.
    func isUnknownToDictionary(_ word: String) -> Bool {
        aospTrieEngine.isReady && !aospTrieEngine.knowsWord(word)
    }

    /// Returns up to 3 word completions for a partial word, ranked by frequency.
    ///
    /// HOW IT WORKS:
    /// 1. UITextChecker.completions() returns all possible completions from the system dictionary
    /// 2. We order those completions by our frequency dictionary, most common first
    ///    (the dictionary answers with a frequency count: higher = more common)
    /// 3. LearnedWordCompletions gives one word the user taught us the first slot (#346)
    /// 4. We return only the top 3 to fill the suggestion bar's 3 slots
    ///
    /// WHY frequency-based ranking:
    /// UITextChecker returns completions in alphabetical order by default. Ranking by
    /// word frequency ensures "les" appears before "lesparre" when typing "le".
    ///
    /// WHY the learned set is read here on every keystroke, with no cache:
    /// it lives in memory, holds tens of entries since #287 stopped learning
    /// words the trie already knows, and this runs on the suggestion queue. A
    /// cache would only add an invalidation to get wrong — the other process
    /// writes to this dictionary too.
    func suggestions(for partialWord: String) -> [String] {
        guard !partialWord.isEmpty else { return [] }

        let nsString = partialWord as NSString
        let range = NSRange(location: 0, length: nsString.length)

        // `?? []` and not an early return: a prefix the system checker has
        // nothing to say about is exactly the case a learned word exists for.
        let completions = textChecker.completions(
            forPartialWordRange: range,
            in: partialWord,
            language: language
        ) ?? []

        let ranked = frequencyDict.sortedMostCommonFirst(completions)
        return LearnedWordCompletions.merge(
            typedPrefix: partialWord,
            learnedWords: UserDictionary.shared.learnedWordsByLastUsed,
            systemCompletions: ranked
        )
    }

    /// Returns the best correction and alternatives for a misspelled word.
    /// Returns nil if the word is correctly spelled or is a user-learned word.
    ///
    /// WHY two-pass lookup:
    /// Pass 1: Check UserDictionary first. Words the user has learned (via rejection
    /// or repetition) are always considered correct -- no trie lookup needed. This
    /// prevents the trie from "correcting" names, slang, or jargon the user has taught.
    /// Pass 2: Delegate to AOSPTrieEngine for proximity-weighted, accent-aware correction
    /// against the 100K+ word binary trie dictionary.
    ///
    /// WHY AOSPTrieEngine instead of SymSpell:
    /// The trie walks candidates during lookup with keyboard proximity scoring,
    /// supporting 100K+ words in ~0.4 MiB per language via mmap. SymSpell pre-generated
    /// all edit-distance deletes, using 15 MiB for just 10K words.
    /// - Parameter isAtSentenceStart: whether the word sits at a sentence start
    ///   in the host document (start-of-field, after newline or after .!?).
    ///   Drives the proper-noun guard (#199): mid-sentence capitalized unknown
    ///   words are preserved. Defaults to `true`, the conservative value —
    ///   callers without position info keep full correction behavior (only the
    ///   position-independent acronym rule applies).
    func spellCheck(
        _ word: String,
        isAtSentenceStart: Bool = true
    ) -> (correction: String, alternatives: [String])? {
        guard !word.isEmpty else { return nil }

        // The user's own contacts and text replacements (#873) outrank every
        // dictionary rule below, the language overrides included.
        if let decision = lexiconDecision(for: word) {
            return lexiconResult(decision, for: word)
        }

        // Language-specific overrides bypass everything — e.g., "ca" is never valid French.
        // Must check before UserDictionary, otherwise typing "ca" twice
        // would "learn" it and block the ça correction permanently.
        if let result = aospTrieEngine.languageOverride(for: word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: result.correction,
                branch: "language-override", prevWord: nil
            )
            #endif
            return result
        }

        // Apostrophe prefix fix: when the user types an apostrophe after an
        // invalid contraction prefix ("v'est"), correct the prefix via keyboard
        // proximity. Gated on the language having any contraction prefixes —
        // currently only French qualifies. Valid FR prefixes are {j,n,s,m,t,d,c,l,qu}.
        // Examples: "v'est" → "c'est", "b'est" → "c'est", "x'ai" → "j'ai".
        //
        // WHY before everything else:
        // Our downstream apostrophe split only validates the part AFTER the
        // apostrophe — "v'est" → checks "est" (valid) → returns nil (no correction).
        // We need to intercept wrong prefixes explicitly.
        if let profile = profile, !profile.contractionPrefixes.isEmpty,
           let corrected = correctApostrophePrefix(word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "apostrophe-prefix", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Two-pass lookup: user dictionary first (learned words are always "correct").
        // Extract the word part after any apostrophe for user dict check, matching
        // the same apostrophe handling that AOSPTrieEngine uses internally.
        let lowered = word.lowercased()
        let wordToCheck: String
        let apostrophePrefix: String?
        if let apoIndex = lowered.lastIndex(of: "'") {
            wordToCheck = String(lowered[lowered.index(after: apoIndex)...])
            apostrophePrefix = String(lowered[...apoIndex])
        } else {
            wordToCheck = lowered
            apostrophePrefix = nil
        }
        if UserDictionary.shared.isLearned(wordToCheck) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "user-learned")
            #endif
            return nil  // User-learned word: no correction needed
        }

        // Accent expansion runs BEFORE wordExists check.
        // "tres" may exist in the trie as a low-frequency word, but "très" is far
        // more common. The accent expansion uses frequency comparison to decide.
        // "deja" → "déjà", "apres" → "après", "tres" → "très"
        // The apostrophe prefix must be reassembled: wordToCheck is only the
        // part after the apostrophe, so "J'etais" checks "etais" → "étais" and
        // the correction is "j'" + "étais", not bare "étais".
        if let accented = aospTrieEngine.accentExpansion(wordToCheck) {
            let full = (apostrophePrefix ?? "") + accented
            let isCapitalized = word.first?.isUppercase == true
            let corrected = isCapitalized ? full.capitalized : full
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "accent", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Valid word guard: if the word exists in the trie dictionary, it's correct.
        // This prevents aggressive corrections like "fais" → "vais".
        // Runs AFTER accent expansion so "tres" → "très" still works.
        if aospTrieEngine.wordExists(wordToCheck) {
            if !aospTrieEngine.wordIsTrusted(wordToCheck) {
                return weakWordCorrection(word, wordToCheck: wordToCheck, isAtSentenceStart: isAtSentenceStart)
            }
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "already-valid")
            #endif
            return nil
        }

        // Contraction expansion: "Cest" → "C'est", "jai" → "j'ai"
        // Runs BEFORE the proper-noun guard: like accent expansion, it's a
        // high-confidence exact transformation (registered prefix + dictionary
        // suffix), so a capitalized "Cest" mid-sentence must correct to "C'est"
        // rather than be preserved as a pseudo-name (and worse, learned).
        if let expanded = aospTrieEngine.contractionExpansion(word) {
            let isCapitalized = word.first?.isUppercase == true
            let corrected = isCapitalized ? expanded.capitalized : expanded
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: corrected, branch: "contraction", prevWord: nil
            )
            #endif
            return (corrected, [])
        }

        // Proper-noun guard (#199): only unknown words reach this point.
        // An unknown capitalized word mid-sentence ("vu Mathilde") or an
        // all-caps acronym ("SNCF") is most likely intentional — preserve it
        // instead of forcing the closest dictionary word. Runs AFTER the
        // high-confidence branches (languageOverride, UserDictionary, accent
        // and contraction expansion) but BEFORE the fuzzy ones (split, trie).
        // The preserved word is then learned via handleSpace's recordUsage path,
        // protecting future occurrences even at sentence start.
        if ProperNounGuard.isLikelyProperNoun(word: word, isAtSentenceStart: isAtSentenceStart) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "likely-proper-noun")
            #endif
            return nil
        }

        // Word splitting + single-word correction comparison.
        //
        // Strategy (informed by real user feedback + debug log analysis):
        //
        // 1. Split with bigram evidence (any strategy) → accept. The n-gram
        //    model confirms this is a real phrase pattern.
        //
        // 2. Split with boundary signal but NO bigram evidence → compare ED.
        //    Our Wikipedia corpus misses colloquial phrases like "pas mal"
        //    (bigram score 0) but the spacebar-neighbor key proves a missed
        //    space. Accept the split only when it fits the input noticeably
        //    better than the trie's single-word correction (split ED + 1 ≤
        //    single ED). This rejects "fonction agités" cases where single-
        //    word correction is at ED 0 or 1 but keeps "pas mal" cases
        //    where single-word "Pascal" is at ED 2 and split ED is 1.
        //
        // 3. No split → fall through to trie single-word correction.
        let evaluation = trySplitWithSignal(wordToCheck)
        let splitResult = evaluation.split
        let splitHasBoundary = evaluation.hasBoundarySignal
        let splitHasBigram = evaluation.hasBigramEvidence
        if let split = splitResult {
            let useSplit: Bool
            if splitHasBigram {
                useSplit = true  // bigram confirmed, accept
            } else if splitHasBoundary {
                // Boundary-only (no bigram): compare with single-word correction via ED
                if let single = aospTrieEngine.spellCheck(word) {
                    let splitJoined = split.replacingOccurrences(of: " ", with: "").lowercased()
                    let splitED = Self.editDistance(wordToCheck, splitJoined)
                    let singleLower = single.correction.lowercased()
                    let singleWordPart: String
                    if let idx = singleLower.lastIndex(of: "'") {
                        singleWordPart = String(singleLower[singleLower.index(after: idx)...])
                    } else {
                        singleWordPart = singleLower
                    }
                    let singleED = Self.editDistance(wordToCheck, singleWordPart)
                    // Accept split only if strictly better fit (split + 1 ≤ single).
                    // "pasnmal": split "pasmal" ED 1, single "pascal" ED 2 → 1+1=2 ≤ 2 ✓
                    // "fonctionnalités": split "fonctionagités" ED ~3, single ED 0/1 → reject ✓
                    useSplit = (splitED + 1) <= singleED
                } else {
                    useSplit = true  // no single-word alternative, accept split
                }
            } else {
                useSplit = false  // direct split rejected without bigram (prevented by trySplit)
            }

            if useSplit {
                let isCapitalized = word.first?.isUppercase == true
                let result = isCapitalized ? (split.prefix(1).uppercased() + split.dropFirst()) : split
                #if DEBUG
                AutocorrectDebugLog.autocorrectDecision(
                    original: word, corrected: result,
                    branch: splitHasBoundary ? "split-boundary" : "split-bigram",
                    prevWord: nil
                )
                #endif
                return (result, [])
            }
            #if DEBUG
            AutocorrectDebugLog.note("split \"\(split)\" rejected (ED comparison favored single-word)")
            #endif
        }

        // Pass 5: trie spell check (proximity-weighted, accent-aware)
        let trieResult = aospTrieEngine.spellCheck(word)
        #if DEBUG
        if let r = trieResult {
            let corrFreq = aospTrieEngine.wordFrequency(r.correction.lowercased())
            let altsWithFreq = r.alternatives.map { alt in
                (alt, aospTrieEngine.wordFrequency(alt.lowercased()))
            }
            AutocorrectDebugLog.trieCandidates(
                word: word, correction: r.correction,
                correctionFreq: corrFreq, alternatives: altsWithFreq
            )
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: r.correction, branch: "trie", prevWord: nil
            )
        } else {
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "no-trie-candidate")
        }
        #endif
        return trieResult
    }

    /// A word the dictionary knows but flags weak (its long tail of rarer words): kept
    /// when the trie scorer still ranks it first, replaced when a neighbour wins.
    ///
    /// WHY not trusted like the others: measured on tools/typing-bench, trusting the
    /// 59,000 added words as typed lets typos of common words land on them and stay
    /// ("already-valid"); running them through the scorer keeps every gain of the
    /// larger vocabulary without that cost. Only the scorer runs here: the split and
    /// contraction passes are for non-words.
    private func weakWordCorrection(
        _ word: String, wordToCheck: String, isAtSentenceStart: Bool
    ) -> (correction: String, alternatives: [String])? {
        if ProperNounGuard.isLikelyProperNoun(word: word, isAtSentenceStart: isAtSentenceStart) {
            return nil
        }
        guard let result = aospTrieEngine.spellCheck(word),
              result.correction.lowercased() != word.lowercased() else {
            #if DEBUG
            AutocorrectDebugLog.autocorrectSkipped(word: word, reason: "weak-word-kept")
            #endif
            return nil
        }
        #if DEBUG
        AutocorrectDebugLog.autocorrectDecision(
            original: word, corrected: result.correction, branch: "weak-word", prevWord: nil
        )
        #endif
        return result
    }

    /// Predict next words based on context (1-2 previous words).
    /// Falls back to top frequent words when no n-gram match exists.
    ///
    /// WHY fallback to frequency:
    /// When the user types a word not in the n-gram model (rare word, name, etc.),
    /// showing the most common words is better than an empty suggestion bar.
    /// These are the words most likely to follow any context.
    func predictNextWords(after words: [String]) -> [String] {
        let predictions = aospTrieEngine.predictNextWords(after: words)
        if predictions.isEmpty {
            return frequencyDict.topWords(count: 3)
        }
        return predictions
    }

    /// Spell check with the previous word available.
    ///
    /// The previous word no longer reorders corrections. The bigram rerank that did
    /// (trie candidates plus n-gram neighbours at edit distance 1, reordered by
    /// bigram score) cost 0.05, 0.5 and 1.2 points of words right at tap noise
    /// 0.20, 0.30 and 0.40 on 36,922 words of French sentences
    /// (tools/typing-bench/context_bench.cpp): it overrode the tap evidence the
    /// trie already weighs. `previousWord` stays in the signature for the
    /// language overrides and lexicon verdicts, and for a context model that
    /// beats the bench.
    func spellCheck(
        _ word: String,
        previousWord: String?,
        isAtSentenceStart: Bool = true
    ) -> (correction: String, alternatives: [String])? {
        // Lexicon verdicts (#873) come first: they are authoritative.
        if let decision = lexiconDecision(for: word) {
            return lexiconResult(decision, for: word)
        }

        // Language overrides are authoritative too (#222: "je lai" → "l'ai").
        if let override = aospTrieEngine.languageOverride(for: word) {
            #if DEBUG
            AutocorrectDebugLog.autocorrectDecision(
                original: word, corrected: override.correction,
                branch: "language-override", prevWord: previousWord
            )
            #endif
            return override
        }

        return spellCheck(word, isAtSentenceStart: isAtSentenceStart)
    }

    /// Levenshtein edit distance between two strings. O(n*m) but strings are
    /// short (< 20 chars) so this is sub-microsecond.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                if a[i - 1] == b[j - 1] {
                    dp[j] = prev
                } else {
                    dp[j] = min(prev, dp[j], dp[j - 1]) + 1
                }
                prev = temp
            }
        }
        return dp[b.count]
    }

    // MARK: - Word Splitting

    /// Keys adjacent to the spacebar on each keyboard layout.
    /// When the user presses one of these instead of space, two words get fused.
    /// On AZERTY: bottom row is W-X-C-V-B-N — only N (rightmost, next to space/comma)
    /// and B are truly adjacent to the spacebar. V was previously included but is
    /// 3 keys from space, causing false splits like "calvier" → "cal hier".
    /// On QWERTY: bottom row is Z-X-C-V-B-N-M — M is rightmost (next to space),
    /// N and B are close enough to count.
    /// QWERTZ shares the QWERTY set: its bottom row is Y-X-C-V-B-N-M, so the three
    /// keys adjacent to the spacebar are the same ones (#151).
    private static let azertySpacebarNeighbors: Set<Character> = ["n", "b", ","]
    private static let qwertySpacebarNeighbors: Set<Character> = ["n", "b", "m"]

    /// Short words (2 chars) that are allowed to appear as split parts.
    /// Standard split requires ≥3 chars per part to avoid noise like "ho ne",
    /// but French has many 2-char pronouns/articles/connectives that commonly
    /// start missed-space compounds (e.g., "tuboeux" should split as "tu peux",
    /// "jepense" as "je pense"). This allowlist restricts the 2-char relaxation
    /// to words that are structurally plausible as a left/right split half.
    /// The set is shared by every language. Each word past the French ones was
    /// admitted only after the split-pass bench (tools/split-pass-bench, #499) showed
    /// it recovers glues and adds no false or wrong split in any language. "de",
    /// "of", "el", "zu", "so" and "sa" were measured and left out for adding one, and
    /// "no" for trapping on "queno" (#499).
    private static let shortSplitAllowlist: Set<String> = [
        "je", "tu", "il", "on", "me", "te", "se", "ne",
        "le", "la", "un", "du", "au", "en",
        "et", "ou", "ni", "si", "ça", "où", "ce",
        "pu", "vu",
        "to", "is", "in", "at", "by", "be", "go", "my",
        "es", "mi", "lo",
        "an", "er"
    ]

    /// Whether a split part is long enough or belongs to the short-word allowlist.
    private static func isValidSplitPart(_ part: String) -> Bool {
        return part.count >= 3 || (part.count == 2 && shortSplitAllowlist.contains(part))
    }

    // MARK: - Apostrophe Prefix Correction

    /// Valid single-char contraction prefixes in French.
    /// "qu'" is handled separately since it's 2 chars.
    private static let validFrenchApostrophePrefixes: Set<Character> =
        ["j", "n", "s", "m", "t", "d", "c", "l"]

    /// Proximity groups for AZERTY — each key maps to the valid apostrophe prefix
    /// it likely substitutes when typed by mistake. Built from AZERTY bottom/middle
    /// row adjacency:
    /// - V is next to C → v'est → c'est
    /// - B is next to N → b'est → n'est (less common but possible)
    /// - G, H are next to J → g'ai/h'ai → j'ai
    private static let azertyApostrophePrefixFix: [Character: Character] = [
        "v": "c",  // v'est → c'est
        "x": "c",  // x'est → c'est (x is left of c on AZERTY)
        "f": "d",  // f'est → d'est (not a real contraction, skip?)
        "g": "j",  // g'ai → j'ai (g is left of h which is left of j)
        "h": "j",  // h'ai → j'ai
        "k": "j",  // k'ai → j'ai
        "b": "n",  // b'est → n'est
        "y": "t",  // y'es → t'es (adjacent on AZERTY top row)
        "r": "t",  // r'es → t'es
        "u": "t"  // u'es → t'es
    ]

    /// Correct a word with invalid apostrophe prefix via keyboard proximity.
    /// "v'est" → "c'est", "b'a" → "n'a", etc.
    /// Returns nil if no fix applies.
    private func correctApostrophePrefix(_ word: String) -> String? {
        let lower = word.lowercased()
        guard let apoIdx = lower.firstIndex(of: "'") else { return nil }

        // Only 1-char prefix is handled here (qu' is 2-char and handled elsewhere).
        let prefixDistance = lower.distance(from: lower.startIndex, to: apoIdx)
        guard prefixDistance == 1 else { return nil }

        let prefixChar = lower[lower.startIndex]
        let suffix = String(lower[lower.index(after: apoIdx)...])
        guard !suffix.isEmpty else { return nil }

        // Prefix is already valid — let the normal pipeline handle it.
        if Self.validFrenchApostrophePrefixes.contains(prefixChar) {
            return nil
        }

        // Look up the proximity fix for this prefix character.
        guard let fixedPrefix = Self.azertyApostrophePrefixFix[prefixChar] else {
            return nil
        }

        // Verify the suffix is a real word (avoids correcting random typos like
        // "v'azxy" where the suffix is garbage).
        guard aospTrieEngine.wordExists(suffix) else { return nil }

        // Reassemble with the corrected prefix and original casing.
        let isCapitalized = word.first?.isUppercase == true
        let corrected = "\(fixedPrefix)'\(suffix)"
        return isCapitalized ? (corrected.prefix(1).uppercased() + corrected.dropFirst()) : corrected
    }

    /// The winning split plus the evidence backing it.
    ///
    /// WHY a struct and not a tuple: three labelled members is one past what the
    /// project lints for, and a named type also stops the caller destructuring
    /// three same-shaped values positionally.
    private struct SplitEvaluation {
        /// The winning "left right" split, or nil when nothing qualified.
        let split: String?
        /// The split used a spacebar-neighbor char — strong physical evidence.
        let hasBoundarySignal: Bool
        /// The pair (left, right) has a bigram score > 0 — linguistic evidence.
        let hasBigramEvidence: Bool
    }

    /// A boundary-split candidate while the loop below is still looking for the
    /// best one. Same reason as SplitEvaluation for being a struct.
    private struct BoundaryCandidate {
        let split: String
        let score: UInt32
        let hasBigram: Bool
    }

    /// Wrapper around trySplit that returns the winning split plus flags
    /// describing the evidence backing it. Caller decides whether to accept.
    ///
    /// Evidence sources:
    /// - boundarySignal: split used a spacebar-neighbor char — strong physical evidence
    /// - bigramEvidence: pair (left, right) has bigram score > 0 — linguistic evidence
    ///
    /// Rules for returning a candidate:
    /// - Direct split (no boundary): REQUIRES bigram. Prevents "honnête lent".
    /// - Boundary split: allowed WITHOUT bigram (our n-gram corpus misses
    ///   colloquial phrases like "pas mal"). Caller applies an ED comparison
    ///   with the single-word correction to decide.
    ///
    /// Boundary splits with bigram evidence win over those without.
    private func trySplitWithSignal(_ word: String) -> SplitEvaluation {
        let chars = Array(word)
        // Minimum absolute part length 2; each part must also pass isValidSplitPart
        // which requires either ≥3 chars or membership in the short-word allowlist.
        // This lets "tu peux" split from "tuboeux" while still blocking "ho ne"
        // from "honne" (since "ho" is not allowlisted).
        let minPartLength = 2
        guard chars.count >= 4 else {
            return SplitEvaluation(split: nil, hasBoundarySignal: false, hasBigramEvidence: false)
        }

        let spacebarNeighbors = LayoutType.active == .azerty
            ? Self.azertySpacebarNeighbors
            : Self.qwertySpacebarNeighbors

        var bestBoundary: BoundaryCandidate?
        var bestBigram: (split: String, score: UInt32)?

        /// Score a candidate pair. Returns (score, hasBigram).
        /// Candidates with bigram get a large bonus (1000×bigram), making them
        /// strictly win over non-bigram candidates at the same freq product.
        func scorePair(left: String, right: String) -> (UInt32, Bool) {
            let bigram = aospTrieEngine.bigramScore(for: right, after: left)
            let freqProduct = UInt32(aospTrieEngine.wordFrequency(left))
                            * UInt32(aospTrieEngine.wordFrequency(right))
            if bigram > 0 {
                return (freqProduct + UInt32(bigram) * 1000, true)
            } else {
                return (freqProduct, false)
            }
        }

        /// True when `score` should replace the current best, including the case
        /// where there is no current best yet.
        /// WHY not the shorter `score > (current ?? 0)`: a first candidate scoring
        /// zero must still beat "no candidate at all", and that shorthand would
        /// silently drop it.
        func improves(_ score: UInt32, over current: UInt32?) -> Bool {
            guard let current else { return true }
            return score > current
        }

        for splitPos in minPartLength...(chars.count - minPartLength) {
            let left = String(chars[0..<splitPos])
            let right = String(chars[splitPos...])

            // Both parts must meet the length/allowlist requirement.
            guard Self.isValidSplitPart(left) else { continue }

            let leftExists = aospTrieEngine.wordExists(left)
            let rightExists = aospTrieEngine.wordExists(right)

            // Boundary-char removal at spacebar neighbor (bigram OPTIONAL)
            if splitPos < chars.count, spacebarNeighbors.contains(chars[splitPos]) {
                let rightAfter = String(chars[(splitPos + 1)...])
                if Self.isValidSplitPart(rightAfter) {
                    // Case A: both halves valid as-is
                    if leftExists && aospTrieEngine.wordExists(rightAfter) {
                        let (s, hasBi) = scorePair(left: left, right: rightAfter)
                        if improves(s, over: bestBoundary?.score) {
                            bestBoundary = BoundaryCandidate(
                                split: "\(left) \(rightAfter)", score: s, hasBigram: hasBi
                            )
                        }
                    }
                    // Case B: right half needs spell correction (min 3 chars to avoid
                    // correcting short garbage into arbitrary words).
                    if leftExists && !aospTrieEngine.wordExists(rightAfter) && rightAfter.count >= 3,
                       let c = aospTrieEngine.spellCheck(rightAfter) {
                        let (s, hasBi) = scorePair(left: left, right: c.correction)
                        if improves(s, over: bestBoundary?.score) {
                            bestBoundary = BoundaryCandidate(
                                split: "\(left) \(c.correction)", score: s, hasBigram: hasBi
                            )
                        }
                    }
                }
            }

            // Direct split — REQUIRES bigram evidence (no boundary signal to fall back on)
            guard Self.isValidSplitPart(right) else { continue }
            if leftExists && rightExists {
                let (s, hasBi) = scorePair(left: left, right: right)
                if hasBi, improves(s, over: bestBigram?.score) {
                    bestBigram = ("\(left) \(right)", s)
                }
            }
        }

        // Priority: boundary > direct bigram (boundary has stronger physical signal)
        let winner: String?
        let hasBoundary: Bool
        let hasBigramEv: Bool
        if let b = bestBoundary {
            winner = b.split
            hasBoundary = true
            hasBigramEv = b.hasBigram
        } else if let bg = bestBigram {
            winner = bg.split
            hasBoundary = false
            hasBigramEv = true
        } else {
            winner = nil
            hasBoundary = false
            hasBigramEv = false
        }

        #if DEBUG
        if winner != nil {
            AutocorrectDebugLog.splitEvaluation(
                word: word, boundaryBest: bestBoundary?.split,
                bigramBest: bestBigram?.split, winner: winner
            )
        }
        #endif
        return SplitEvaluation(
            split: winner, hasBoundarySignal: hasBoundary, hasBigramEvidence: hasBigramEv
        )
    }

}
