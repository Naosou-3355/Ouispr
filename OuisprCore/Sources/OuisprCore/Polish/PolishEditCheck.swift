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

        // Edits against the output, applied back to front so ranges stay valid.
        enum Edit { case remove(Range<String.Index>), replace(Range<String.Index>, String), insert(String.Index, String) }
        var edits: [(at: String.Index, edit: Edit)] = []
        for op in align(inTokens.map(\.key), outTokens.map(\.key)) {
            switch op {
            case let .insert(j):
                guard outTokens[j].key == "ne" else { continue }
                // The token and the space after it.
                var range = outTokens[j].range
                if range.upperBound < polished.endIndex, polished[range.upperBound] == " " {
                    range = range.lowerBound..<polished.index(after: range.upperBound)
                }
                edits.append((range.lowerBound, .remove(range)))
            case let .replace(i, j):
                guard outTokens[j].key == "n'" + inTokens[i].key else { continue }
                edits.append((outTokens[j].range.lowerBound,
                              .replace(outTokens[j].range, rebuilt(outTokens[j].surface, word: inTokens[i].word))))
            case let .delete(i, beforeOutput):
                guard protectedWords.contains(inTokens[i].key), keepsSpeakersWord(at: i, in: inTokens) else { continue }
                if beforeOutput < outTokens.count {
                    edits.append((outTokens[beforeOutput].range.lowerBound, .insert(outTokens[beforeOutput].range.lowerBound, inTokens[i].word + " ")))
                } else {
                    edits.append((polished.endIndex, .insert(polished.endIndex, " " + inTokens[i].word)))
                }
            }
        }
        guard !edits.isEmpty else { return polished }
        var result = polished
        for (_, edit) in edits.sorted(by: { $0.at > $1.at }) {
            switch edit {
            case let .remove(range): result.removeSubrange(range)
            case let .replace(range, text): result.replaceSubrange(range, with: text)
            case let .insert(index, text): result.insert(contentsOf: text, at: index)
            }
        }
        return result
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
