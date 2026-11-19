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
    public static let maximumWords = 25

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
            blockedPhrases: ["en fait", "je veux dire", "tu vois", "tu sais"]
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
                             "question mark", "exclamation mark", "exclamation point"]
        )
    }
}
