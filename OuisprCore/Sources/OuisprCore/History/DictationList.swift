// OuisprCore/Sources/OuisprCore/History/DictationList.swift
// The rules behind Home's recent dictations and the history's sections.
import Foundation

/// What Home's three recent rows and the history's sections show (« Banc Ouispr
/// épuré », 27 Nov 2026): which records have words to show, the repeats left out, and
/// the period each one is filed under. Pure, so the screens only draw.
public enum DictationList {

    /// How many dictations Home lists.
    public static let homeCount = 3

    /// Whether a record's text has anything to read: a letter or a digit. A dictation
    /// that came back as « … » is saved, but a row of punctuation says nothing.
    public static func hasWords(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    /// The items without the repeats that follow each other: the same words dictated
    /// twice in a row are one row, the newest (audit of 26 Nov 2026, n°9, two « C'est pas
    /// mal » side by side). Compared without case, surrounding spaces or final punctuation.
    public static func droppingRepeats<T>(_ items: [T], text: (T) -> String) -> [T] {
        var kept: [T] = []
        var previous: String?
        for item in items {
            let key = text(item)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .lowercased()
            if key != previous || key.isEmpty { kept.append(item) }
            previous = key
        }
        return kept
    }

    /// The records a list shows: those with words, without consecutive repeats.
    public static func shown<T>(_ items: [T], text: (T) -> String) -> [T] {
        droppingRepeats(items.filter { hasWords(text($0)) }, text: text)
    }

    // MARK: - Periods

    /// The history's sections, newest first.
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

    /// The items filed by period, in the periods' order, each keeping the items' order;
    /// periods with nothing in them left out.
    public static func sections<T>(_ items: [T], now: Date, calendar: Calendar = .current,
                                   date: (T) -> Date) -> [(period: Period, items: [T])] {
        var buckets: [Period: [T]] = [:]
        for item in items {
            buckets[Period.of(date(item), now: now, calendar: calendar), default: []].append(item)
        }
        return Period.allCases.compactMap { period in
            buckets[period].map { (period, $0) }
        }
    }
}
