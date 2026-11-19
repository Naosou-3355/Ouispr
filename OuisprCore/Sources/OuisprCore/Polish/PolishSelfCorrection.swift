// OuisprCore/Sources/OuisprCore/Polish/PolishSelfCorrection.swift
// Applies a spoken self-correction ("samedi, non pardon, dimanche") without the model.
import Foundation

/// Rule 10 of the prompt, done by rule where the shape is unambiguous.
///
/// WHY: on 145 readable self-corrections (big bench, 2026-11-19) the model applied
/// 5.5 % of them, and when it did the lost-word guardrail refused its output, since
/// the retracted words are gone. The common shape needs no judgement:
///
///     … <retracted> <cue> <replacement> …
///
/// where the replacement starts like the retracted part did — the same word
/// (`devant la mairie, pardon, devant la gare`), or a word of the same kind (a
/// weekday for a weekday, a determiner for a determiner). The retracted part and the
/// cue are removed; the replacement stays where it was said.
///
/// Only explicit cues are used. A bare `non` answers questions, a bare `plutôt` and a
/// bare `enfin` are adverbs: alone they are left to the model. A cue at the start of
/// a sentence retracts nothing and is left alone too. French only.
public enum PolishSelfCorrection {

    /// Longest first, so `non pardon` wins over `pardon`.
    static let cues: [[String]] = [
        ["non", "je", "me", "suis", "trompé"], ["non", "je", "me", "suis", "trompée"],
        ["je", "me", "suis", "trompé"], ["je", "me", "suis", "trompée"],
        ["ah", "non", "pardon"], ["en", "fait", "non"], ["non", "pardon"], ["enfin", "non"],
        ["ah", "non"], ["non", "attends"], ["non", "attend"], ["ou", "plutôt"], ["non", "plutôt"],
        ["je", "veux", "dire"], ["pardon"]
    ]

    /// Cues that are ordinary words just as often (`non`, `enfin`), and the forms
    /// Parakeet hears for real cues (`en fin`, `ou attend`). They only count when what
    /// follows restarts the retracted part on a word of a closed kind — a weekday, a
    /// month, a preposition, a determiner — the shape a correction has and an
    /// ordinary `non` does not.
    static let weakCues: [[String]] = [
        ["ou", "attends"], ["ou", "attend"], ["ou", "non"], ["en", "fin"],
        ["attends"], ["attend"], ["enfin"], ["non"]
    ]

    static let restartWords: Set<String> = [
        "à", "au", "aux", "devant", "derrière", "chez", "dans", "sur", "sous", "vers", "avec",
        "pour", "de", "du", "des", "le", "la", "les", "l'", "un", "une", "mon", "ma", "mes",
        "ton", "ta", "tes", "son", "sa", "ses", "ce", "cette", "ces"
    ]

    /// How far back the retracted part may start, in words.
    static let window = 6

    static let kinds: [Set<String>] = [
        ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"],
        ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août",
         "septembre", "octobre", "novembre", "décembre"],
        ["le", "la", "les", "l'", "un", "une", "des", "du", "mon", "ma", "mes", "ton", "ta",
         "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs", "ce", "cette", "ces"],
        ["demain", "aujourd'hui", "hier", "ce"]
    ]

    public static func apply(_ text: String, language: SupportedLanguage) -> String {
        guard language == .french else { return text }
        var current = text
        // One correction per pass; a dictation rarely holds more than a few.
        for _ in 0..<4 {
            guard let next = applyOnce(current), next != current else { break }
            current = next
        }
        return current
    }

    static func applyOnce(_ text: String) -> String? {
        let tokens = PolishEditCheck.tokens(text)
        let keys = tokens.map(\.key)
        for start in tokens.indices {
            let strong = cues.first { matches($0, keys, at: start) }
            guard let cue = strong ?? weakCues.first(where: { matches($0, keys, at: start) }) else { continue }
            let cueEnd = start + cue.count            // first token after the cue
            guard cueEnd < tokens.count, start > 0 else { continue }
            if strong == nil, !restartWords.contains(keys[cueEnd]),
               !kinds[0].union(kinds[1]).contains(keys[cueEnd]) { continue }
            // `je veux dire la vérité` is the verb; only `…, je veux dire …` corrects.
            if cue == ["je", "veux", "dire"], !tokens[start - 1].surface.hasSuffix(",") { continue }
            // `pardon pour le bruit`, `pardon de te déranger`: an apology.
            if cue == ["pardon"], ["pour", "de", "d'"].contains(keys[cueEnd]) { continue }
            // A sentence ending right before the cue: nothing to retract in it.
            if endsSentence(tokens[start - 1].surface) { continue }
            // `ou plutôt` in a question offers a choice (`la plage ou plutôt la
            // montagne ?`): nothing is taken back.
            if cue.contains("plutôt"), questionEnds(text[tokens[cueEnd].range.lowerBound...]) { continue }
            let first = keys[cueEnd]
            let lo = max(0, start - window)
            var retractFrom: Int?
            for p in stride(from: start - 1, through: lo, by: -1) {
                // A sentence boundary between here and the replacement, even after
                // the cue (`C'est ton vélo, non ? La sonnette…`) or spaced the French
                // way (`du pain ? Ah non…`): nothing is taken back across it.
                if crossesSentence(text[tokens[p].range.lowerBound..<tokens[cueEnd].range.lowerBound]) { break }
                // A weak cue only restarts on the same word, a weekday or a month: a
                // determiner of another noun (`Le chef m'a dit non, la réunion…`) is
                // the next clause, not a correction.
                let kindMatches = strong == nil
                    ? kinds[0...1].contains { $0.contains(keys[p]) && $0.contains(first) }
                    : sameKind(keys[p], first)
                if keys[p] == first || kindMatches { retractFrom = p; break }
            }
            guard let from = retractFrom else { continue }
            // Remove from the retracted word to the start of the replacement.
            var result = text
            let range = tokens[from].range.lowerBound..<tokens[cueEnd].range.lowerBound
            let opensSentence = from == 0 || endsSentence(tokens[from - 1].surface)
            result.replaceSubrange(range, with: "")
            if opensSentence, let i = Optional(range.lowerBound), i < result.endIndex,
               let ch = result[i...].first, ch.isLowercase {
                result.replaceSubrange(i..<result.index(after: i), with: String(ch).uppercased())
            }
            return result
        }
        return nil
    }

    static func matches(_ cue: [String], _ keys: [String], at start: Int) -> Bool {
        guard start + cue.count <= keys.count else { return false }
        return zip(cue, keys[start..<(start + cue.count)]).allSatisfy { $0 == $1 }
    }

    static func sameKind(_ a: String, _ b: String) -> Bool {
        kinds.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Whether the sentence running from here ends with `?`.
    static func questionEnds(_ rest: Substring) -> Bool {
        rest.first { ".?!…".contains($0) } == "?"
    }

    /// Whether a sentence ends inside `span`: `. ? ! …` followed by a space.
    static func crossesSentence(_ span: Substring) -> Bool {
        var previous: Character?
        for ch in span {
            if ch.isWhitespace, let mark = previous, ".?!…".contains(mark) { return true }
            previous = ch
        }
        return false
    }

    static func endsSentence(_ surface: String) -> Bool {
        guard let last = surface.last else { return false }
        return ".?!…".contains(last)
    }
}
