// OuisprCore/Sources/OuisprCore/TypingBench/TypingBench.swift
// The typing bench: fixed phrases, typed with one keyboard then another, scored the same way.
import Foundation

/// One phrase as the user typed it.
public struct TypingBenchTrial: Codable, Equatable, Sendable {
    /// The phrase shown on screen.
    public let target: String
    /// What the text field held when the user pressed Return.
    public let typed: String
    /// Seconds from the first to the last edit of the field (Return excluded).
    public let seconds: Double

    public init(target: String, typed: String, seconds: Double) {
        self.target = target
        self.typed = typed
        self.seconds = seconds
    }
}

/// One run of the bench with one keyboard.
public struct TypingBenchSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// The keyboard the user said they used ("Ouispr", "Apple"). The app cannot read
    /// which keyboard is up, so this is the user's own label.
    public let keyboard: String
    public let date: Date
    public let trials: [TypingBenchTrial]

    public init(id: UUID = UUID(), keyboard: String, date: Date = Date(), trials: [TypingBenchTrial]) {
        self.id = id
        self.keyboard = keyboard
        self.date = date
        self.trials = trials
    }
}

/// The three numbers the bench reports.
public struct TypingBenchScore: Equatable, Sendable {
    /// Words per minute, a word being 5 characters (the text-entry convention).
    public let wordsPerMinute: Double
    /// Share of the target words that came out exactly right, after the keyboard's
    /// corrections and the user's own.
    public let wordAccuracy: Double
    /// Character-level errors left in the text: edit distance over the longer of
    /// the two strings ("uncorrected error rate").
    public let characterErrorRate: Double
    public let trialCount: Int
}

/// The phrases of the bench. Everyday messages, 6 to 9 words, with the accents,
/// apostrophes and hyphens French typing actually meets. No final punctuation: how a
/// keyboard ends a sentence is not what is measured.
///
/// NEVER EDIT A PHRASE once results exist: sessions typed on an old phrase would no
/// longer compare with new ones. Add a new list instead.
public enum TypingBenchPhrases {
    public static let french: [String] = [
        "Je serai en retard de dix minutes ce soir",
        "Tu peux acheter du pain en rentrant",
        "On se retrouve devant la gare à midi",
        "Merci pour ton message, je te rappelle demain",
        "Il fait beau, on pourrait aller marcher",
        "J'ai oublié mes clés chez toi hier",
        "La réunion est déplacée à jeudi matin",
        "Est-ce que tu as vu le dernier épisode",
        "Je t'envoie l'adresse du restaurant tout de suite",
        "Les enfants dorment déjà, passe sans sonner",
        "Pense à réserver les billets de train",
        "Le colis est arrivé ce matin à la maison",
        "Je vais faire les courses avant le dîner",
        "Bon anniversaire, profite bien de ta journée",
        "Nous partons en vacances la semaine prochaine",
        "Peux-tu vérifier si la porte est fermée",
        "Le médecin m'a donné rendez-vous lundi",
        "Il reste encore un peu de gâteau au frigo",
        "Je préfère qu'on en parle de vive voix",
        "Envoie-moi une photo quand tu seras arrivé"
    ]
}

/// Scores trials. Pure functions, so the numbers on the iPhone are the numbers the
/// tests check.
public enum TypingBenchScoring {

    /// What is not the keyboard's fault is not counted: typographic apostrophes and
    /// quotes (iOS "smart punctuation" turns ' into ’), no-break spaces, runs of
    /// spaces, and spaces at either end. Case and accents ARE counted: a missing
    /// accent or capital is a real error in French.
    public static func normalize(_ text: String) -> String {
        var result = text
        for (from, to) in [("\u{2019}", "'"), ("\u{2018}", "'"), ("\u{201C}", "\""),
                           ("\u{201D}", "\""), ("\u{00A0}", " "), ("\u{202F}", " ")] {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Levenshtein distance: insertions, deletions and substitutions all cost 1.
    public static func editDistance<Element: Equatable>(_ lhs: [Element], _ rhs: [Element]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for (i, left) in lhs.enumerated() {
            current[0] = i + 1
            for (j, right) in rhs.enumerated() {
                current[j + 1] = Swift.min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + (left == right ? 0 : 1)
                )
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    /// Scores a set of trials as one block: errors and time are summed first, then
    /// divided, so a long phrase weighs more than a short one (an average of ratios
    /// would let one 3-word phrase count as much as a 9-word one).
    ///
    /// Returns nil for no trials.
    public static func score(_ trials: [TypingBenchTrial]) -> TypingBenchScore? {
        guard !trials.isEmpty else { return nil }
        var characters = 0
        var seconds = 0.0
        var wordErrors = 0
        var targetWords = 0
        var characterErrors = 0
        var characterSpan = 0
        for trial in trials {
            let target = normalize(trial.target)
            let typed = normalize(trial.typed)
            // Soukoreff & MacKenzie: the time runs from the first character, so the
            // first one is not counted in the speed.
            if trial.seconds > 0, typed.count > 1 {
                characters += typed.count - 1
                seconds += trial.seconds
            }
            let targetTokens = target.split(separator: " ").map(String.init)
            let typedTokens = typed.split(separator: " ").map(String.init)
            wordErrors += Swift.min(editDistance(targetTokens, typedTokens), targetTokens.count)
            targetWords += targetTokens.count
            characterErrors += editDistance(Array(target), Array(typed))
            characterSpan += Swift.max(target.count, typed.count)
        }
        let wordsPerMinute = seconds > 0 ? Double(characters) / 5 / (seconds / 60) : 0
        let wordAccuracy = targetWords > 0 ? 1 - Double(wordErrors) / Double(targetWords) : 0
        let characterErrorRate = characterSpan > 0 ? Double(characterErrors) / Double(characterSpan) : 0
        return TypingBenchScore(
            wordsPerMinute: wordsPerMinute,
            wordAccuracy: wordAccuracy,
            characterErrorRate: characterErrorRate,
            trialCount: trials.count
        )
    }

    /// Every trial typed with one keyboard, across all its sessions.
    public static func score(keyboard: String, in sessions: [TypingBenchSession]) -> TypingBenchScore? {
        score(sessions.filter { $0.keyboard == keyboard }.flatMap(\.trials))
    }
}

/// Keeps the sessions in the app's own defaults. The keyboard never reads them, so
/// they stay out of the App Group. The phrases are fixed text, not the user's own
/// writing, so keeping what was typed exposes nothing private.
public final class TypingBenchStore: @unchecked Sendable {

    public static let shared = TypingBenchStore()
    public static let sessionsKey = "ouispr.typingBench.sessions"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Oldest first. An unreadable value reads as no session rather than crashing.
    public func all() -> [TypingBenchSession] {
        guard let data = defaults.data(forKey: Self.sessionsKey) else { return [] }
        return (try? JSONDecoder().decode([TypingBenchSession].self, from: data)) ?? []
    }

    public func append(_ session: TypingBenchSession) {
        guard !session.trials.isEmpty else { return }
        save(all() + [session])
    }

    public func delete(id: UUID) {
        save(all().filter { $0.id != id })
    }

    public func deleteAll() {
        defaults.removeObject(forKey: Self.sessionsKey)
    }

    private func save(_ sessions: [TypingBenchSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Self.sessionsKey)
    }
}

/// The plain-text summary the bench shares, readable in a message as it is.
public enum TypingBenchReport {

    public static func text(sessions: [TypingBenchSession], keyboards: [String]) -> String {
        var lines = ["Banc de frappe Ouispr"]
        for keyboard in keyboards {
            guard let score = TypingBenchScoring.score(keyboard: keyboard, in: sessions) else { continue }
            let count = sessions.filter { $0.keyboard == keyboard }.count
            lines.append("\(keyboard) (\(count) session(s), \(score.trialCount) phrases) : \(summary(score))")
        }
        lines.append("")
        lines.append("Sessions :")
        let dateFormatter = ISO8601DateFormatter()
        for session in sessions {
            guard let score = TypingBenchScoring.score(session.trials) else { continue }
            lines.append("\(dateFormatter.string(from: session.date)) \(session.keyboard) : \(summary(score))")
        }
        return lines.joined(separator: "\n")
    }

    /// "38.2 mots/min, 96.1 % de mots justes, 1.2 % d'erreurs de caractères"
    public static func summary(_ score: TypingBenchScore) -> String {
        String(
            format: "%.1f mots/min, %.1f %% de mots justes, %.1f %% d'erreurs de caractères",
            score.wordsPerMinute, score.wordAccuracy * 100, score.characterErrorRate * 100
        )
    }
}
