// OuisprCore/Sources/OuisprCore/Polish/FrenchElision.swift
import Foundation

/// French elision, restored in code: « le écoute » becomes « l'écoute ».
///
/// The speech models write each word they hear, and a fast « l'écoute » can come out as
/// « le écoute », which the polish engine then keeps (audit of 26 Nov 2026, n°13: Alex
/// said « L'écoute »). The rule is fixed grammar, so it is applied here rather than
/// asked of the model: le, la, de, que, je, ne, se, me, te before a vowel or a silent h
/// lose their vowel.
///
/// Conservative on purpose:
/// - an aspirated h (« le héros », « la hauteur ») and a semi-vowel y (« le yaourt »)
///   keep the full word, as do « le onze » and « le oui »;
/// - a pronoun after an imperative (« laisse-le entrer », « puis-je avoir ») is joined
///   by a hyphen and is never elided;
/// - nothing next to a URL, an email address or code is touched (a token with `@`,
///   `://`, `www.`, `/`, `_`, `=`, braces or brackets, or anything between backticks).
public enum FrenchElision {

    static let elidable: Set<String> = ["le", "la", "de", "que", "je", "ne", "se", "me", "te"]

    /// Words starting with an aspirated h, or otherwise never elided before.
    static let blocking: Set<String> = [
        "hache", "haie", "haine", "haïr", "hall", "halte", "hamac", "hamburger", "hameau",
        "hamster", "hanche", "handicap", "handball", "hangar", "hanter", "harceler", "hardi",
        "hareng", "haricot", "harpe", "hasard", "hâte", "hausse", "haut", "haute", "hauteur",
        "havre", "hérisson", "héron", "héros", "hibou", "hiérarchie", "hippie", "hobby",
        "hockey", "homard", "hongrois", "honte", "hors", "hotte", "houx", "hublot", "huit",
        "huitième", "hurler", "hutte", "onze", "onzième", "oui", "ouf"
    ]

    private static let vowels = Set("aeiouyàâäéèêëîïôöùûüœæ")

    public static func apply(_ text: String) -> String {
        guard text.contains(" ") else { return text }
        // Tokens with their following whitespace, so the text is rebuilt byte for byte.
        var tokens: [(word: String, space: String)] = []
        var word = ""
        var space = ""
        for character in text {
            if character == " " {
                space.append(character)
            } else {
                if !space.isEmpty {
                    tokens.append((word, space))
                    word = ""
                    space = ""
                }
                word.append(character)
            }
        }
        tokens.append((word, space))

        var out = ""
        var inCode = false
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let backticks = token.word.filter { $0 == "`" }.count
            defer { if backticks % 2 == 1 { inCode.toggle() } }
            if !inCode, backticks == 0, index + 1 < tokens.count,
               let elided = elide(token.word, before: tokens[index + 1].word) {
                out += elided + tokens[index + 1].word + tokens[index + 1].space
                if tokens[index + 1].word.filter({ $0 == "`" }).count % 2 == 1 { inCode.toggle() }
                index += 2
                continue
            }
            out += token.word + token.space
            index += 1
        }
        return out
    }

    /// The elided form of `word` (« l' », « qu' », with its case) when the next word
    /// calls for it, nil otherwise.
    static func elide(_ word: String, before next: String) -> String? {
        let lower = word.lowercased()
        guard elidable.contains(lower), let first = next.first else { return nil }
        guard !isProtected(next) else { return nil }
        let nextLower = next.lowercased()
        let bare = nextLower.prefix { $0.isLetter }
        guard !blocking.contains(String(bare)) else { return nil }
        let initial = Character(String(first).lowercased())
        if initial == "y" {
            // « j'y », « n'y », « qu'y »: the word y itself; « le yaourt » keeps its e.
            guard bare == "y" else { return nil }
        } else if initial != "h" {
            guard vowels.contains(initial) else { return nil }
        }
        var stem = String(word.dropLast())
        if word.count == 2, word == word.uppercased(), next != next.uppercased() {
            // « Le écoute »: only the first letter was a capital.
            stem = String(stem.prefix(1))
        }
        return stem + "'"
    }

    /// A URL, an email address, a path or code.
    static func isProtected(_ token: String) -> Bool {
        if token.contains("@") || token.contains("://") || token.lowercased().hasPrefix("www.") { return true }
        return token.contains { "/_={}[]<>`\\".contains($0) }
    }
}
