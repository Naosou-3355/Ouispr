// OuisprCore/Sources/OuisprCore/Polish/PolishCleanInput.swift
// Whether a transcript is already clean enough to skip the polish model.
import Foundation

/// A transcript the free polish has nothing to do on, decided without the model.
///
/// WHY: the model is all of the polish's time (1.6 s for a short sentence and 6 s for
/// a long one on an M3 Max, roughly two to three times that on an iPhone), and on a
/// short sentence Parakeet already wrote with capitals and punctuation it rewrites the
/// same text. Every rule of the free-polish prompt (`PolishNaturalPromptFR`) that this
/// check cannot rule out is a reason to run the model, so the check only says "clean"
/// when none of them can apply:
///
/// - rule 1–2: the text starts with a capital, ends with `. ? ! …`, and every
///   sentence inside it starts with a capital;
/// - rule 3: no spelled-out number (`vingt`, `trois`) to turn into digits;
/// - rule 4: no verbal punctuation left (`virgule`, `point`) after the pre-pass;
/// - rule 5: no line-break marker to keep in place and capitalise after;
/// - rule 6: no word said twice in a row;
/// - rule 7: no filler (`euh`, `tu vois`);
/// - rule 10: no self-correction cue (`non`, `pardon`, `je veux dire`, `en fait`);
/// - short (`maximumWords`): the longer the dictation, the likelier it hides an ASR
///   error (rule 8) this check cannot see, and the less the skip is worth guessing.
///
/// Only French and English have word lists; any other language is never "clean".
/// What is lost on a skip is what no rule here can see: an accent Parakeet left off,
/// a one-letter typo, a misheard word.
public enum PolishCleanInput {

    /// Longest transcript, in words, that can skip the model.
    public static let maximumWords = 40

    public static func isClean(_ text: String, language: SupportedLanguage) -> Bool {
        guard let lists = WordLists.for(language) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("<<NL>>"), !trimmed.contains("\n") else { return false }
        guard let first = trimmed.first(where: { $0.isLetter || $0.isNumber }),
              first.isUppercase || first.isNumber,
              let last = trimmed.last, ".?!…".contains(last) else { return false }

        let words = Self.words(trimmed)
        guard (1...maximumWords).contains(words.count) else { return false }

        // Every sentence after the first starts with a capital.
        let scalars = Array(trimmed)
        for i in scalars.indices where ".?!…".contains(scalars[i]) {
            if let next = scalars[(i + 1)...].first(where: { !$0.isWhitespace && !"»\")".contains($0) }),
               next.isLetter, !next.isUppercase {
                return false
            }
        }

        for (i, w) in words.enumerated() {
            if i > 0, w == words[i - 1] { return false }
            if lists.blocked.contains(w) { return false }
        }
        let joined = " " + words.joined(separator: " ") + " "
        for phrase in lists.blockedPhrases where joined.contains(" \(phrase) ") { return false }
        // Marks the model adds and Parakeet leaves out (rule 1): a comma after a
        // greeting and the name that follows it, after a sentence-opening discourse
        // word, before "s'il te plaît"; a colon after an announcement.
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in lists.missingCommaPatterns
        where pattern.firstMatch(in: trimmed, range: range) != nil { return false }
        return true
    }

    /// Lowercased words: letters and digits, with apostrophes and hyphens as breaks.
    static func words(_ text: String) -> [String] {
        let separators = CharacterSet.letters.union(.decimalDigits).inverted
        return text.lowercased().components(separatedBy: separators).filter { !$0.isEmpty }
    }

    struct WordLists {
        let blocked: Set<String>
        let blockedPhrases: [String]
        let missingCommaPatterns: [NSRegularExpression]

        init(blocked: Set<String>, blockedPhrases: [String], missingComma: [String]) {
            self.blocked = blocked
            self.blockedPhrases = blockedPhrases
            // Literal patterns written below; a typo in one is a programming error.
            // swiftlint:disable:next force_try
            self.missingCommaPatterns = missingComma.map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        }

        static func `for`(_ language: SupportedLanguage) -> WordLists? {
            switch language {
            case .french: return french
            case .english: return english
            case .spanish, .german: return nil
            }
        }

        static let french = WordLists(
            blocked: [
                // fillers (rule 7)
                "euh", "euhh", "heu", "hum", "hmm", "bah", "ben", "hein",
                // self-correction cues (rule 10)
                "non", "pardon", "enfin", "plutôt", "attends", "trompé", "trompée",
                // verbal punctuation (rule 4)
                "virgule", "point", "points", "ligne", "guillemet", "guillemets",
                "parenthèse", "tiret", "slash",
                // spelled-out numbers (rule 3); `un`/`une` are articles and stay
                "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix",
                "onze", "douze", "treize", "quatorze", "quinze", "seize", "vingt", "vingts",
                "trente", "quarante", "cinquante", "soixante", "cent", "cents", "mille",
            ],
            blockedPhrases: ["en fait", "je veux dire", "tu vois", "tu sais"],
            missingComma: [
                // "Salut Manu comment tu vas" → "Salut Manu, comment tu vas"
                #"(^|[.?!…]\s+)(salut|bonjour|bonsoir|coucou|hello|hey|yo|merci)(\s+\p{Lu}[\p{L}-]*)?+\s+\p{L}"#,
                // "Et franchement le mode" → "Et franchement, le mode"
                #"(^|[.?!…]\s+)(et\s+|mais\s+)?(franchement|honnêtement|sincèrement|perso|personnellement|bref|sinon|d['’]ailleurs|écoute|écoutez|du coup|par contre|bon)\s+\p{L}"#,
                // "tout à l'heure s'il te plaît" → "tout à l'heure, s'il te plaît"
                #"\p{L}\s+s['’]il\s+(te|vous)\s+pla[iî]t"#,
                // Announcements the model closes with `:` (rule 1):
                // "il m'a dit un truc de fou, il sort avec Anne" → "un truc de fou : il sort"
                #"\b(truc|chose|histoire)\s+(de\s+(fou|dingue|ouf)|incroyable)\s*,?\s+\p{L}"#,
                #"\b(devine|tu\s+sais|sais-tu)\s+quoi\s*,?\s+\p{L}"#,
                #"\b(bonne|mauvaise|grosse|grande|super|petite)\s+nouvelle\s*,?\s+\p{L}"#,
                #"\bvoilà\s+ce\s+(qu['’]|que\b|qui\b)[^:.?!…]*[.?!…]"#,
                #"\b\d+\s+(choses|trucs|points|questions|options|solutions|raisons)\s*,?\s+\p{L}"#,
                #"\bm['’](a|ont)\s+(répondu|annoncé|avoué|raconté|expliqué)\s*,?\s+\p{L}"#,
                #"\b(petit\s+)?rappel\s*,?\s+\p{L}"#,
                #"\b(est|c['’]est)\s+simple\s*,?\s+\p{L}"#,
                // An email sign-off run into the last sentence ("des questions cordialement
                // Paul"), and a topic change run into the previous one: the model splits
                // them, and the email layout needs them split.
                #"[\p{L},]\s+(bien\s+)?(cordialement|bisous|bises|amicalement|bonne\s+journée|bonne\s+soirée|à\s+bientôt)\b"#,
                #"\p{L}\s+(par\s+ailleurs|d['’]autre\s+part)\b"#,
            ]
        )

        static let english = WordLists(
            blocked: [
                "uh", "uhm", "um", "umm", "er", "erm", "hmm",
                "no", "sorry", "actually", "rather", "wait",
                "comma", "period", "colon", "semicolon", "quote", "dash", "slash",
                "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
                "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty",
                "seventy", "eighty", "ninety", "hundred", "thousand",
            ],
            blockedPhrases: ["i mean", "you know", "scratch that", "new line", "full stop",
                             "question mark", "exclamation mark", "exclamation point"],
            missingComma: [
                #"(^|[.?!…]\s+)(hi|hello|hey|thanks|thank you)(\s+\p{Lu}[\p{L}-]*)?+\s+\p{L}"#,
                #"(^|[.?!…]\s+)(honestly|frankly|anyway|so|well|basically)\s+\p{L}"#,
            ]
        )
    }
}
