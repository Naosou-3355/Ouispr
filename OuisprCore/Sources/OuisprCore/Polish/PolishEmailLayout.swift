// OuisprCore/Sources/OuisprCore/Polish/PolishEmailLayout.swift
// Lays a dictated email out on lines: greeting, body paragraphs, sign-off, signature.
import Foundation

/// Line breaks for a dictation that is an email, decided and placed without the model.
///
/// WHY deterministic: the free-polish contract (ADR 0003) forbids the model to add
/// line breaks, and every attempt at an Email mode invented greetings and sign-offs
/// the speaker never said (`SmartModeCatalogue`, Email). This pass adds no word: it
/// only moves the words the speaker DID say onto their own lines, so it cannot
/// invent anything, and it costs no model time.
///
/// A dictation is laid out only when it carries both ends of an email:
/// - it opens with a greeting followed by a comma (`Bonjour Marc,`), and
/// - it ends with a sign-off (`Cordialement`, `Bonne journée`, `Merci d’avance`),
///   optionally followed by a name of one to three capitalised words,
/// - and at least one end is the register of an email rather than a text message
///   (`Salut Julie, … Bisous.` stays on one line), unless the dictation is long.
///
/// Inside the body, a sentence that opens with a topic change (`Par ailleurs`,
/// `Sinon`, `N’hésite pas`) starts a new paragraph. A dictation that already has a
/// line break is the speaker's own layout and is left alone. French only.
public enum PolishEmailLayout {

    /// Shortest dictation, in words, that is laid out with an informal greeting AND
    /// an informal sign-off. Below it, `Salut …, … Bisous` reads as a text message.
    static let informalMinimumWords = 40

    public static func apply(_ text: String, language: SupportedLanguage?) -> String {
        guard language == .french else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("\n"),
              let greeting = firstMatch(greetingPattern, in: trimmed),
              let closing = firstMatch(closingPattern, in: trimmed),
              greeting.range.upperBound <= closing.range.lowerBound else { return text }

        let greetingText = String(trimmed[greeting.range])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        let body = String(trimmed[greeting.range.upperBound..<closing.range.lowerBound])
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;")))
        guard !body.isEmpty else { return text }

        let formulas = closing.groups[0].map(String.init) ?? ""
        let signature = closing.groups[1].map(String.init)
        let isFormal = greeting.groups[0].map { !informalGreetings.contains($0.lowercased()) } ?? false
            || formulasAreFormal(formulas)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard isFormal || wordCount >= informalMinimumWords else { return text }

        var lines = [greetingText + ","]
        lines.append("")
        lines.append(contentsOf: paragraphs(capitalized(terminated(body))).joined(separator: "\n\n").components(separatedBy: "\n"))
        lines.append("")
        lines.append(contentsOf: closingLines(formulas, signature: signature))
        return lines.joined(separator: "\n")
    }

    // MARK: - Body

    /// A sentence of the body that opens one of these starts a new paragraph.
    static let paragraphOpeners = [
        "par ailleurs", "d'autre part", "d’autre part", "sinon", "autre chose", "concernant",
        "en ce qui concerne", "pour finir", "pour le reste", "de plus", "enfin",
        "n'hésite pas", "n’hésite pas", "n'hésitez pas", "n’hésitez pas",
        "je reste à", "je suis à ta disposition", "je suis à votre disposition"
    ]

    static func paragraphs(_ body: String) -> [String] {
        var result: [String] = []
        var current = ""
        for sentence in sentences(body) {
            let lower = sentence.lowercased()
            if !current.isEmpty, paragraphOpeners.contains(where: { lower.hasPrefix($0) }) {
                result.append(current)
                current = sentence
            } else {
                current = current.isEmpty ? sentence : current + " " + sentence
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Sentences, each with its own end mark, split after `. ? ! …`.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if ".?!…".contains(c), next.isWhitespace {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    // MARK: - Sign-off

    static let informalGreetings: Set<String> = ["salut", "coucou", "hello", "hey", "yo"]
    /// Sign-offs only an email uses. After an informal greeting, anything else
    /// (`À demain`, `Bonne soirée`, `Merci d’avance`, `Bisous`) reads as a text message.
    static let formalFormulaWords = ["cordialement", "bien à", "salutations", "amicalement"]

    static func formulasAreFormal(_ formulas: String) -> Bool {
        let lower = formulas.lowercased()
        return formalFormulaWords.contains { lower.contains($0) }
    }

    /// One line per formula; the last one takes a comma when a signature follows.
    /// `Merci d’avance` before another formula is its own paragraph, as a sentence.
    static func closingLines(_ formulas: String, signature: String?) -> [String] {
        let parts = formulas
            .components(separatedBy: CharacterSet(charactersIn: ".,!"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let formulas = splitFormulas(parts)
        var lines: [String] = []
        for (i, part) in formulas.enumerated() {
            let isLast = i == formulas.count - 1
            let line = capitalized(part)
            if !isLast {
                lines.append(line + ".")
                lines.append("")
            } else {
                lines.append(line + (signature == nil ? "." : ","))
            }
        }
        if let signature {
            lines.append(signature.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
        }
        return lines
    }

    /// `merci d’avance cordialement` said in one breath is two formulas.
    static func splitFormulas(_ parts: [String]) -> [String] {
        parts.flatMap { part -> [String] in
            let lower = part.lowercased()
            for thanks in ["merci d'avance", "merci d’avance"]
            where lower.hasPrefix(thanks) && lower.count > thanks.count + 1 {
                let rest = String(part.dropFirst(thanks.count)).trimmingCharacters(in: .whitespaces)
                return [String(part.prefix(thanks.count)), rest]
            }
            return [part]
        }
    }

    // MARK: - Patterns

    /// `Bonjour Marc,` `Bonjour à tous,` `Madame,` — a greeting word, at most four
    /// more words, then a comma. Group 1 is the greeting word.
    static let greetingPattern = regex(
        #"^(?i:(bonjour|bonsoir|salut|coucou|hello|hey|cher|chère|chers|chères|madame|monsieur|mesdames))\b[^,.!?;:\n]{0,40},\s*"#
    )

    /// The sign-off zone at the very end: one or two formulas, then an optional
    /// signature of one to three capitalised words. Group 1 is the formulas, group 2
    /// the signature.
    ///
    /// A formula that is also ordinary French (`une bonne journée`, `reportée à
    /// demain`) is a sign-off only after a sentence mark or a comma; one that only a
    /// sign-off uses (`cordialement`, `bisous`) may also be run into the last sentence.
    static let closingPattern: NSRegularExpression = {
        let runIn = #"(?:bien cordialement|cordialement|grosses bises|gros bisous|bisous|bises|amicalement|salutations distinguées|à (?:bientôt|très vite))"#
        let bounded = #"(?:bien à (?:vous|toi)|bonne (?:fin de )?(?:journée|soirée|semaine|continuation)|belle (?:journée|soirée)|à (?:plus|demain)|merci d['’]avance)"#
        let formula = "(?:" + runIn + "|" + bounded + ")"
        let lead = #"(?:^|(?<=[.!?…,;])\s*|\s(?=(?i:"# + runIn + #")))"#
        let name = #"\p{Lu}[\p{L}'’-]+(?:\s+\p{Lu}[\p{L}'’-]+){0,2}"#
        return regex(lead + #"((?i:"# + formula + #")(?:[\s,.!]+(?i:"# + formula + #"))?)[\s,.!]*(?:("# + name + #"))?[\s.!]*$"#)
    }()

    // MARK: - Helpers

    struct Match {
        let range: Range<String.Index>
        let groups: [Substring?]
    }

    static func firstMatch(_ pattern: NSRegularExpression, in text: String) -> Match? {
        let ns = NSRange(text.startIndex..., in: text)
        guard let m = pattern.firstMatch(in: text, range: ns),
              let range = Range(m.range, in: text) else { return nil }
        let groups = (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { text[$0] }
        }
        return Match(range: range, groups: groups)
    }

    static func regex(_ pattern: String) -> NSRegularExpression {
        // Literal patterns written above; a typo in one is a programming error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The body ends on a sentence mark: a sign-off said straight after the last
    /// word (`je te redis demain bisous`) leaves it without one.
    static func terminated(_ text: String) -> String {
        guard let last = text.last, !".?!…".contains(last) else { return text }
        return text + "."
    }
}
