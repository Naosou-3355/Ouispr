// OuisprCore/Sources/OuisprCore/Design/WordRevealPlan.swift
// How a dictated text is cut into words and when each one appears.
import Foundation

/// The plan for revealing a text word by word (design V2, bench 3).
///
/// Pure: it decides the cut and the timing, and `RevealingText` draws them.
public struct WordRevealPlan: Equatable, Sendable {
    /// One piece of the text, in reading order.
    public enum Token: Equatable, Sendable {
        /// A word with its punctuation, as it was written.
        case word(String)
        /// The end of a line the text itself asked for.
        case lineBreak
    }

    public let tokens: [Token]
    public let wordCount: Int

    /// Above this many words the text appears in one fade instead.
    ///
    /// WHY a ceiling: every word is its own view while it is revealed. A few dozen
    /// cost nothing; a three-minute dictation is several hundred views blurring at
    /// once, for an effect nobody watches to the end.
    public static let maximumAnimatedWords = 150

    /// Seconds before the first word starts.
    public static let leadIn = 0.1
    /// Seconds between two words in a short text.
    public static let wordInterval = 0.11
    /// Seconds one word takes to come into focus.
    public static let wordDuration = 0.35
    /// The longest the last word may wait. A long text speeds up to fit, so the
    /// reveal never keeps the user from the text they asked for.
    public static let maximumSpread = 2.5

    public init(text: String) {
        var tokens: [Token] = []
        var wordCount = 0
        // "\r\n" is one line break, not two.
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 { tokens.append(.lineBreak) }
            for word in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                tokens.append(.word(String(word)))
                wordCount += 1
            }
        }
        // A text that ends with a line break does not owe the screen an empty line.
        while tokens.last == .lineBreak { tokens.removeLast() }
        self.tokens = tokens
        self.wordCount = wordCount
    }

    /// Whether the words appear one by one, or the text in a single fade.
    public var animatesWordByWord: Bool {
        wordCount > 0 && wordCount <= Self.maximumAnimatedWords
    }

    /// Seconds before the word at `wordIndex` (0 for the first word) starts to appear.
    public func delay(forWordAt wordIndex: Int) -> Double {
        guard wordCount > 1 else { return Self.leadIn }
        let interval = min(Self.wordInterval, Self.maximumSpread / Double(wordCount - 1))
        return Self.leadIn + Double(max(wordIndex, 0)) * interval
    }

    /// Seconds from the start until the last word is fully shown.
    public var totalDuration: Double {
        guard wordCount > 0 else { return 0 }
        return delay(forWordAt: wordCount - 1) + Self.wordDuration
    }
}
