// OuisprCore/Sources/OuisprCore/TranscriptionStyle.swift
// The default look of a dictation: capitals and punctuation, nothing else.

import Foundation

/// How a finished dictation looks when it lands in the text field.
///
/// WHY a separate setting from polish and from the Smart Modes: those decide which
/// **words** end up in the text (fillers removed, a self-correction kept, a list
/// built). A style only decides the **form** around those words: capitals and
/// punctuation. It never adds, removes or changes a word. This is the split Wispr
/// Flow makes too ("Personalized Style only adjusts capitalization, punctuation, and
/// spacing").
///
/// WHY plain string rules rather than a prompt: the style must be instant, must
/// behave the same every time, and must work when Apple Intelligence is missing or
/// polish is off. So it runs as the last step before insertion, on whatever text
/// reached the keyboard — polished, raw or recovered.
///
/// WHY one default style and no per-app style: an iOS keyboard is not told which
/// app it is typing into, so it cannot pick a style per app the way Wispr does on
/// the Mac. Wispr's iPhone app makes the same choice: one default style.
///
/// WHY no "Excited" style (Wispr has one): it adds exclamation marks the speaker
/// never dictated, which breaks the rule that the app never adds to what was said.
///
/// The raw values are what the App Group stores: renaming a case orphans the
/// user's choice, which then falls back to `defaultStyle`.
public enum TranscriptionStyle: String, CaseIterable, Sendable {
    /// Capitals and full punctuation: the text as polish produced it.
    case formal
    /// Capitals and punctuation, but no period at the very end, like a text message.
    case casual
    /// No capital at the start of sentences, no commas, no periods. `?` and `!` stay.
    case veryCasual

    /// Casual, chosen by Alex on 2026-11-21: messages without a final period.
    public static let defaultStyle: TranscriptionStyle = .casual

    /// The stored style. Missing or unknown values fall back to `defaultStyle`.
    public static func current(in defaults: UserDefaults = AppGroup.defaults) -> TranscriptionStyle {
        defaults.string(forKey: SharedKeys.transcriptionStyle)
            .flatMap(TranscriptionStyle.init(rawValue:))
            ?? defaultStyle
    }

    /// `text` in this style. Words are never touched, only capitals and punctuation.
    public func apply(to text: String) -> String {
        switch self {
        case .formal:
            return text
        case .casual:
            return Self.removingFinalPeriod(text)
        case .veryCasual:
            return Self.removingCommasAndPeriods(Self.lowercasingSentenceStarts(text))
        }
    }

    // MARK: - Casual

    /// Removes one period at the very end of the text, ignoring trailing whitespace.
    ///
    /// Left alone: an ellipsis (`...`, `…`), `?` and `!`, and an abbreviation whose
    /// period belongs to the word (`etc.`).
    static func removingFinalPeriod(_ text: String) -> String {
        var characters = Array(text)
        guard let last = characters.lastIndex(where: { !$0.isWhitespace }),
              characters[last] == "." else {
            return text
        }
        if last > 0, characters[last - 1] == "." {
            return text
        }
        let wordBefore = String(characters[..<last].reversed().prefix(while: { $0.isLetter }).reversed())
        if Self.abbreviationsKeepingTheirPeriod.contains(wordBefore.lowercased()) {
            return text
        }
        characters.remove(at: last)
        return String(characters)
    }

    /// Words whose final period is part of the word, not the end of a sentence.
    static let abbreviationsKeepingTheirPeriod: Set<String> = ["etc"]

    // MARK: - Very casual

    /// Lowercases the first letter of every sentence: the start of the text, after
    /// `.`, `!`, `?` or `…`, and after a line break (so each list line too).
    ///
    /// A word with another capital inside it is left alone, so acronyms and names
    /// written that way survive (`PR`, `OK`, `iPhone`, `McDo`). A name that opens a
    /// sentence is lowercased like any other word: the text cannot tell it from a
    /// common word, and this style is lowercase by choice.
    static func lowercasingSentenceStarts(_ text: String) -> String {
        let characters = Array(text)
        var result: [Character] = []
        result.reserveCapacity(characters.count)
        var atSentenceStart = true
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isLetter {
                var end = index
                while end < characters.count, characters[end].isLetter {
                    end += 1
                }
                let word = characters[index..<end]
                let restHasCapital = word.dropFirst().contains { $0.isUppercase }
                if atSentenceStart, !restHasCapital {
                    result.append(contentsOf: Array(character.lowercased()))
                    result.append(contentsOf: word.dropFirst())
                } else {
                    result.append(contentsOf: word)
                }
                atSentenceStart = false
                index = end
                continue
            }
            if character.isNumber {
                atSentenceStart = false
            } else if Self.sentenceEnders.contains(character) || character.isNewline {
                atSentenceStart = true
            }
            result.append(character)
            index += 1
        }
        return String(result)
    }

    /// Removes every comma and period that ends a clause: one followed by a space,
    /// a line break or the end of the text.
    ///
    /// Left alone: a decimal (`3,5`, `3.5`, where no space follows), an ellipsis,
    /// and every other mark (`?`, `!`, `:`, `;`, quotes, apostrophes).
    static func removingCommasAndPeriods(_ text: String) -> String {
        let characters = Array(text)
        var result: [Character] = []
        result.reserveCapacity(characters.count)
        for (index, character) in characters.enumerated() {
            guard character == "," || character == "." else {
                result.append(character)
                continue
            }
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            let previous: Character? = index > 0 ? characters[index - 1] : nil
            let endsAClause = next.map { $0.isWhitespace } ?? true
            let isPartOfEllipsis = character == "." && (next == "." || previous == ".")
            if endsAClause, !isPartOfEllipsis {
                continue
            }
            result.append(character)
        }
        return String(result)
    }

    /// Marks after which a new sentence starts.
    static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
}
