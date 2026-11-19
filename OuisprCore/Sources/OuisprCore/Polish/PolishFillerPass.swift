// OuisprCore/Sources/OuisprCore/Polish/PolishFillerPass.swift
// Removes pure hesitation sounds before the model, and the stray marks around them.
import Foundation

/// `euh`, `uh`, `hum` removed without the model.
///
/// WHY: the prompt already asks the model to drop them (rule 7, "always"), and on a
/// long dictation it does not: a 492-word real dictation kept all three of its
/// hesitations (alex01, 2026-11-19). These words carry no meaning in any context, so
/// removing them needs no judgement, and doing it here means the clean-input gate can
/// skip the model on a sentence whose only flaw was an `euh`.
///
/// Only sounds that are never words are listed: `bah`, `ben`, `bon` and `quoi` mean
/// something often enough to stay with the model.
///
/// Around the removed sound:
/// - its own comma or period goes with it (`Euh. La pastille` → `La pastille`);
/// - when it opened a sentence, the next word takes the capital;
/// - a period Parakeet put right before a sentence-opening hesitation, followed by a
///   lowercase continuation, is not touched: what the model or the gate sees is the
///   speaker's text minus the sound, nothing re-punctuated.
public enum PolishFillerPass {

    static let sounds: [SupportedLanguage: [String]] = [
        .french: ["euh", "euhh", "euuh", "heu", "hum", "hmm", "uh", "uhm", "um"],
        .english: ["uh", "uhh", "uhm", "um", "umm", "erm", "hmm"],
        .spanish: ["ehm", "emm"],
        .german: ["äh", "ähm", "öhm", "hm", "hmm"],
    ]

    public static func apply(_ text: String, language: SupportedLanguage) -> String {
        guard let list = sounds[language], !list.isEmpty else { return text }
        let alternation = list.joined(separator: "|")
        // The sound, optionally followed by its own mark, as a whole word.
        let pattern = #"(?i)(?<![\p{L}\p{N}'’-])(?:"# + alternation + #")(?![\p{L}\p{N}'’-])\s*[,.…]*\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var out = text
        var removed = false
        let ns = out as NSString
        let matches = regex.matches(in: out, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: out) else { continue }
            // Did the sound open a sentence (start of text, or after . ? ! … or a newline)?
            let before = out[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let opensSentence = before.isEmpty || ".?!…\n".contains(before.last ?? ".")
            out.removeSubrange(range)
            removed = true
            if opensSentence {
                let idx = range.lowerBound
                if idx < out.endIndex, let first = out[idx...].first, first.isLowercase {
                    let next = out.index(after: idx)
                    out.replaceSubrange(idx..<next, with: String(first).uppercased())
                }
            }
        }
        guard removed else { return text }
        return tidy(out)
    }

    /// Spaces and marks left behind: double spaces, a space before a comma or a
    /// period, a comma right after a period, a leading mark.
    static func tidy(_ text: String) -> String {
        var out = text
        let rules: [(String, String)] = [
            (#"[ \t]{2,}"#, " "),
            (#" +([,.…])"#, "$1"),
            (#"([.?!…]),+"#, "$1"),
            (#",{2,}"#, ","),
            (#"^[\s,.…]+"#, ""),
        ]
        for (pattern, replacement) in rules {
            out = out.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
