// OuisprCore/Sources/OuisprCore/Polish/PolishEditCheck.swift
// Keeps the model's good edits and undoes, one by one, the two it is known to get wrong.
import Foundation

/// Edit-by-edit review of the free polish's output, instead of all-or-nothing.
///
/// WHY: the guardrails accept or refuse a whole output. On a long dictation that is
/// the wrong grain: one dropped `nous` (alex01: "recentrer la map sur nous" lost its
/// `nous`, which reverses who the map centres on) either throws away every good comma
/// around it, or ships with it. This pass aligns the output on the input word by word
/// and reverts only:
///
/// 1. **a dropped meaning word** — a pronoun or a negation (`nous`, `pas`, `jamais`)
///    the speaker said and the model removed, unless the speaker took it back aloud
///    (a self-correction cue sits next to it, rule 10) or said it twice in a row (a
///    stutter, rule 6);
/// 2. **an added `ne`** — the written negation the prompt forbids (`on peut pas` stays
///    `on peut pas`): a `ne` token the input did not have is removed, and `n’y` /
///    `n’a` that the input said as `y` / `a` go back to the input's form.
///
/// Every other edit — punctuation, capitals, removed hesitations, digits, repaired
/// words — is kept as the model wrote it. French only; other languages are returned
/// unchanged.
public enum PolishEditCheck {

    /// Words whose loss changes who does what, or whether it happens.
    static let protectedWords: Set<String> = [
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "me", "te", "se", "moi", "toi", "lui", "leur", "eux",
        "pas", "jamais", "rien", "personne", "aucun", "aucune", "sans"
    ]

    /// Self-correction cues (rule 10): a deletion next to one is the speaker's own.
    static let cueWords: Set<String> = [
        "non", "pardon", "enfin", "plutôt", "attends", "trompé", "trompée", "veux", "fait"
    ]

    /// How far from a deleted word a cue still makes the deletion the speaker's.
    static let cueWindow = 4

    public static func review(polished: String, input: String, language: SupportedLanguage?) -> String {
        guard language == .french else { return polished }
        let inTokens = tokens(input)
        let outTokens = tokens(polished)
        guard !inTokens.isEmpty, !outTokens.isEmpty else { return polished }

        var edits: [TextEdit] = []
        // Restored words, by the output word they go back before, in spoken order.
        var restored: [Int: [String]] = [:]
        for op in align(inTokens.map(\.key), outTokens.map(\.key)) {
            switch op {
            case let .insert(j):
                if outTokens[j].key == "ne" { edits.append(removingNe(at: j, in: outTokens, polished: polished)) }
            case let .replace(i, j):
                guard outTokens[j].key == "n'" + inTokens[i].key else { continue }
                edits.append(TextEdit(range: outTokens[j].range,
                                      text: rebuilt(outTokens[j].surface, word: inTokens[i].word)))
            case let .delete(i, beforeOutput):
                guard protectedWords.contains(inTokens[i].key), keepsSpeakersWord(at: i, in: inTokens) else { continue }
                restored[beforeOutput, default: []].append(inTokens[i].word)
            }
        }
        for (position, words) in restored {
            edits.append(restoring(words, before: position, in: outTokens, input: inTokens, polished: polished))
        }
        guard !edits.isEmpty else { return polished }
        // Applied back to front so the ranges still ahead stay valid.
        var result = polished
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: edit.text)
        }
        return result
    }

    /// One change to the output: `range` of it becomes `text`.
    struct TextEdit {
        let range: Range<String.Index>
        let text: String
    }

    /// An added `ne` and the space after it removed. When it opened the sentence
    /// (`Ne touche pas à ça.`), the next word takes its capital.
    static func removingNe(at j: Int, in out: [Token], polished: String) -> TextEdit {
        var range = out[j].range
        if range.upperBound < polished.endIndex, polished[range.upperBound] == " " {
            range = range.lowerBound..<polished.index(after: range.upperBound)
        }
        guard out[j].surface.first?.isUppercase == true, j + 1 < out.count,
              range.upperBound == out[j + 1].range.lowerBound,
              let first = out[j + 1].surface.first, first.isLowercase else {
            return TextEdit(range: range, text: "")
        }
        return TextEdit(range: range.lowerBound..<polished.index(after: range.upperBound),
                        text: String(first).uppercased())
    }

    /// Dropped words written back before output word `position`. At the start of a
    /// sentence the first restored word takes the capital (`Nous on part demain.`,
    /// not `nous On part demain.`), and the word after it goes back to the lowercase
    /// the speaker's text had — a name the speaker's text capitalised keeps it.
    static func restoring(_ words: [String], before position: Int, in out: [Token],
                          input: [Token], polished: String) -> TextEdit {
        let joined = words.joined(separator: " ")
        guard position < out.count else {
            return TextEdit(range: polished.endIndex..<polished.endIndex, text: " " + joined)
        }
        let next = out[position]
        let at = next.range.lowerBound
        let opensSentence = position == 0 || PolishSelfCorrection.endsSentence(out[position - 1].surface)
        guard opensSentence, let first = next.surface.first, first.isUppercase else {
            return TextEdit(range: at..<at, text: joined + " ")
        }
        let capitalised = joined.prefix(1).uppercased() + joined.dropFirst()
        let lowercaseInInput = input.contains { $0.word == next.word.lowercased() }
        guard lowercaseInInput else { return TextEdit(range: at..<at, text: capitalised + " ") }
        return TextEdit(range: at..<polished.index(after: at), text: capitalised + " " + String(first).lowercased())
    }

    /// A deleted protected word is the speaker's to keep unless it is one half of an
    /// immediate repeat, or a self-correction cue is within `cueWindow` words.
    static func keepsSpeakersWord(at i: Int, in input: [Token]) -> Bool {
        let key = input[i].key
        if i > 0, input[i - 1].key == key { return false }
        if i + 1 < input.count, input[i + 1].key == key { return false }
        let lo = max(0, i - cueWindow), hi = min(input.count - 1, i + cueWindow)
        return !input[lo...hi].contains { cueWords.contains($0.key) }
    }

    /// `n’y` written back as the input's `y`, keeping the output's trailing marks.
    static func rebuilt(_ surface: String, word: String) -> String {
        let trailing = surface.reversed().prefix { !$0.isLetter && !$0.isNumber }
        return word + String(trailing.reversed())
    }

    // MARK: - Tokens and alignment

    struct Token {
        let range: Range<String.Index>
        let surface: String
        /// The surface stripped of punctuation, for writing a word back.
        let word: String
        /// Lowercased, typographic apostrophe folded, for comparing.
        let key: String
    }

    static func tokens(_ text: String) -> [Token] {
        var result: [Token] = []
        var index = text.startIndex
        let keep = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'’-"))
        while index < text.endIndex {
            guard !text[index].isWhitespace else { index = text.index(after: index); continue }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            let surface = String(text[index..<end])
            let word = surface.trimmingCharacters(in: keep.inverted)
            if !word.isEmpty {
                let key = word.lowercased().replacingOccurrences(of: "’", with: "'")
                result.append(Token(range: index..<end, surface: surface, word: word, key: key))
            }
            index = end
        }
        return result
    }

    enum Op {
        case insert(Int)
        case replace(Int, Int)
        /// Input word `i` has no output counterpart; it belongs before output index.
        case delete(Int, beforeOutput: Int)
    }

    /// Word alignment by longest common subsequence; unmatched runs are paired as
    /// replacements left to right, and the remainder is deletion or insertion.
    static func align(_ a: [String], _ b: [String]) -> [Op] {
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var ops: [Op] = []
        var i = 0, j = 0
        var pendingDeletes: [Int] = [], pendingInserts: [Int] = []
        func flush() {
            let paired = min(pendingDeletes.count, pendingInserts.count)
            for k in 0..<paired { ops.append(.replace(pendingDeletes[k], pendingInserts[k])) }
            for d in pendingDeletes.dropFirst(paired) { ops.append(.delete(d, beforeOutput: j)) }
            for ins in pendingInserts.dropFirst(paired) { ops.append(.insert(ins)) }
            pendingDeletes = []; pendingInserts = []
        }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                flush(); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                pendingInserts.append(j); j += 1
            } else {
                pendingDeletes.append(i); i += 1
            }
        }
        flush()
        return ops
    }
}
