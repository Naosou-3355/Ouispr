// OuisprCore/Sources/OuisprCore/TextCorrection/LinkLikeToken.swift
// Keeps autocorrect out of URLs, e-mail addresses and paths.
//
// WHY: the word the space bar corrects is only the letters before the cursor
// ("pagge" in "https://exemple.com/pagge"). Corrected, it breaks the link, and
// the user may not notice before sending it. A link is never a typo the
// dictionary can fix, so the whole token is left alone.

import Foundation

public enum LinkLikeToken {

    /// Whether the run of non-space characters that ends at the cursor looks like a
    /// URL, an e-mail address or a path.
    ///
    /// Rules, on that run:
    /// - contains "://" ("https://…", "ftp://…"), or starts with "www.";
    /// - contains "@" after at least one character ("nom@exemple.fr"; "@pseudo"
    ///   alone is a handle, left to the other rules);
    /// - contains "/" ("exemple.com/page", "~/Documents", "et/ou");
    /// - contains a dot with a letter or digit right before and right after it
    ///   ("exemple.com", "index.html"). A dot at the end ("fin.") is punctuation.
    public static func isAtCursor(context: String) -> Bool {
        let token = trailingToken(of: context)
        guard token.count >= 3 else { return false }
        if token.contains("://") || token.lowercased().hasPrefix("www.") { return true }
        if let at = token.firstIndex(of: "@"), at > token.startIndex { return true }
        if token.contains("/") { return true }
        return hasInnerDot(token)
    }

    /// The characters before the cursor back to the last whitespace.
    static func trailingToken(of context: String) -> Substring {
        var start = context.endIndex
        while start > context.startIndex {
            let previous = context.index(before: start)
            if context[previous].isWhitespace { break }
            start = previous
        }
        return context[start...]
    }

    private static func hasInnerDot(_ token: Substring) -> Bool {
        let characters = Array(token)
        guard characters.count >= 3 else { return false }
        for index in 1..<(characters.count - 1) where characters[index] == "." {
            let before = characters[index - 1], after = characters[index + 1]
            if (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber) {
                return true
            }
        }
        return false
    }
}
