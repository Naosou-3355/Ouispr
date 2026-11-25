// OuisprCore/Sources/OuisprCore/History/DictationCloud.swift
// The rules behind Home's recent cards and the history's drifting card cloud.
import Foundation

/// The rules of the card cloud (« Fiche historique et accueil V1 », 24 Nov 2026): the card's
/// short title, the periods the history is sorted by, how cards are spread over rows, and
/// the drift itself. Pure, so the screens only draw.
public enum DictationCloud {

    // MARK: - Title

    /// The card's short title: the first two or three words of the dictation's first
    /// sentence, without their punctuation, the first letter capitalised.
    ///
    /// WHY taken from the text and not written by a model: a card is drawn as soon as the
    /// dictation is saved, offline, and a model call per card would cost the battery the
    /// keyboard is careful with. Three words are what fits a 96 pt card at the default size.
    public static func title(for text: String, maxWords: Int = 3) -> String {
        let firstSentence = text
            .split(whereSeparator: { ".!?\n".contains($0) })
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? ""
        var words = Array(firstSentence
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
            .prefix(maxWords))
        // A title does not end on a word that only leads to the next one: « Je serai en »
        // reads as cut, « Je serai » does not.
        while words.count > 1, let last = words.last, danglingWords.contains(last.lowercased()) {
            words.removeLast()
        }
        let joined = words.joined(separator: " ")
        guard let first = joined.first else { return "" }
        return first.uppercased() + joined.dropFirst()
    }

    /// Articles, prepositions and conjunctions, in French and English, that a title
    /// must not end on.
    static let danglingWords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "du", "de", "d", "à", "au", "aux", "en",
        "pour", "par", "sur", "dans", "avec", "et", "ou", "que", "qui", "ce", "mon", "ma", "mes",
        "the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "with", "my"
    ]

    /// The width a card gives its title: about 8.5 pt a character at 16 pt, 18 pt of
    /// padding on each side, between 116 and 220 pt. Estimated rather than measured so a
    /// row knows its length, and so where it wraps, before it is laid out.
    public static func cardWidth(forTitle title: String) -> Double {
        min(220, max(116, Double(title.count) * 8.5 + 36))
    }

    // MARK: - Periods

    /// The history's four periods, the pills of its bar.
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case today, yesterday, week, older

        public var id: String { rawValue }

        /// The period `date` falls in, seen from `now`: today, yesterday, the six days
        /// before, or anything older.
        public static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> Period {
            let day = calendar.startOfDay(for: date)
            let today = calendar.startOfDay(for: now)
            let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            switch days {
            case ..<1: return .today
            case 1: return .yesterday
            case 2...7: return .week
            default: return .older
            }
        }
    }

    // MARK: - Rows

    /// Home's two rows: three cards then two, the newest first.
    public static func homeRows<T>(_ items: [T]) -> [[T]] {
        let recent = Array(items.prefix(5))
        return [Array(recent.prefix(3)), Array(recent.dropFirst(3))].filter { !$0.isEmpty }
    }

    /// The history's rows: the cards dealt in turn, so the newest sit at the head of the
    /// first rows, `perRow` cards a row at most.
    public static func cloudRows<T>(_ items: [T], perRow: Int = 4) -> [[T]] {
        guard !items.isEmpty, perRow > 0 else { return [] }
        let count = (items.count + perRow - 1) / perRow
        var rows = Array(repeating: [T](), count: count)
        for (index, item) in items.enumerated() {
            rows[index % count].append(item)
        }
        return rows
    }

    // MARK: - Drift

    /// The drift's speed, the reference video's (Alex's choice): 10 pt/s.
    public static let driftSpeed: Double = 10
    /// How fast the drift reaches its speed and stops: a first-order ramp, 0.13 s.
    public static let driftRamp: Double = 0.13
    /// How long the drift waits after the finger lifts before resuming.
    public static let resumeDelay: Double = 1.5
}

/// One drifting row: its position along its own period, its speed, and the fling the
/// finger leaves it with.
///
/// The row draws its cards several times over, so `x` only ever has to stay within one
/// period (`unit`, the cards' width with their gaps): wrapping it by a whole period
/// changes nothing on screen.
public struct DriftTrack: Equatable, Sendable {
    /// Offset of the first copy of the cards, in `(-2 * unit, 0]`.
    public private(set) var x: Double
    /// The row's period: its cards and their gaps.
    public let unit: Double
    /// +1 drifts to the right, -1 to the left.
    public let direction: Double
    /// A row's share of the speed: the second row drifts at 0.8 so the two never line up.
    public let speedFactor: Double
    /// The drift speed reached so far, ramping toward its target.
    public private(set) var speed: Double = 0
    /// What a flick left, decaying.
    public private(set) var fling: Double = 0

    public init(unit: Double, direction: Double, speedFactor: Double = 1, start: Double = 0) {
        self.unit = max(1, unit)
        self.direction = direction
        self.speedFactor = speedFactor
        self.x = start
        wrap()
    }

    /// Advance by `dt` seconds toward `targetSpeed` (0 while held, under Reduce Motion or
    /// while listening; `DictationCloud.driftSpeed` otherwise).
    public mutating func step(_ dt: Double, targetSpeed: Double) {
        guard dt > 0 else { return }
        let ramp = 1 - exp(-dt / DictationCloud.driftRamp)
        speed += (targetSpeed - speed) * ramp
        x += (direction * speed * speedFactor + fling) * dt
        fling *= exp(-dt * 3.2)
        if abs(fling) < 2 { fling = 0 }
        wrap()
    }

    /// The finger moved the row by `dx` since the last call.
    public mutating func drag(by dx: Double) {
        x += dx
        fling = 0
        wrap()
    }

    /// The finger lifted at `velocity` pt/s; capped so a hard flick stays readable.
    public mutating func release(velocity: Double) {
        fling = min(1600, max(-1600, velocity))
    }

    private mutating func wrap() {
        while x > 0 { x -= unit }
        while x <= -2 * unit { x += unit }
    }
}
