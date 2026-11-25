// OuisprCore/Sources/OuisprCore/History/TranscriptionSearch.swift
// The rule the History screen's search field applies to the saved transcriptions.
import Foundation

/// Which saved transcriptions a search query finds (#621).
///
/// WHY the rule lives here and not in `HistoryView`: what counts as a match is a
/// product decision with test cases attached (`ecole` must find `école`), and the
/// app target has no test bundle. The view only owns the field and the list.
///
/// WHY a linear filter and no index: the store caps the history at a few hundred
/// short records held in memory (#453 allows at most 1000), so scanning them on
/// every keystroke costs less than keeping an index in step with every append,
/// edit and delete.
public enum TranscriptionSearch {

    /// Case- and diacritic-insensitive, so `ecole` and `Ecole` both find `école`
    /// and `école` finds a transcript that lost its accents. Apostrophes are
    /// folded separately, see `apostrophes`.
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Whether `record` is found by `query`.
    ///
    /// Only the text is searched. The language and the engine are not search terms
    /// (#621 v1): a query of `fr` finding every French dictation would bury the
    /// one transcript that contains the letters. A voice note's summary is not
    /// searched either, because it is not what the card shows.
    ///
    /// A query that is empty once trimmed matches everything, which is what makes
    /// clearing the field restore the whole list.
    public static func matches(_ record: TranscriptionRecord, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return true }
        return contains(record.text, needle)
    }

    /// The records `query` finds, in the order they were given (newest first, as
    /// the store keeps them).
    public static func filter(_ records: [TranscriptionRecord], query: String) -> [TranscriptionRecord] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return records }
        return records.filter { contains($0.text, needle) }
    }

    /// What a search finds once the free window applies (Pro offer, 25 Nov 2026).
    public struct Result: Equatable {
        /// The records shown, newest first.
        public let found: [TranscriptionRecord]
        /// How many older records also match but sit outside the free window.
        /// Zero when the search is unlimited or the query is empty.
        public let olderMatches: Int
    }

    /// `filter`, limited to the records of the last `windowDays` days unless
    /// `unlimited`.
    ///
    /// WHY an empty query is never limited: clearing the field must restore the
    /// whole list. The history itself is free; only searching it far back is Pro.
    /// The older matches are counted, not dropped silently, so the screen can say
    /// what Pro would find.
    public static func search(_ records: [TranscriptionRecord], query: String,
                              now: Date, windowDays: Int, unlimited: Bool) -> Result {
        let found = filter(records, query: query)
        guard !unlimited, !normalized(query).isEmpty else {
            return Result(found: found, olderMatches: 0)
        }
        let cutoff = now.addingTimeInterval(-TimeInterval(windowDays) * 86_400)
        let recent = found.filter { $0.createdAt >= cutoff }
        return Result(found: recent, olderMatches: found.count - recent.count)
    }

    /// The apostrophes a search field can receive, folded to the straight one.
    ///
    /// WHY: `.diacriticInsensitive` does not treat them as the same character, and
    /// they do not arrive the same way. The transcripts carry a straight `'`, and so
    /// does the Ouispr keyboard; Apple's keyboard types a curly `’` with smart
    /// punctuation on. Measured on device for #621: `l'école` typed on Apple's
    /// keyboard did not find a transcript containing `l'école`. U+2018 and U+02BC
    /// are folded too, because they reach a text field as well.
    private static let apostrophes: Set<Character> = ["\u{2019}", "\u{2018}", "\u{02BC}"]

    /// Whether `text` contains `needle`, the needle already trimmed and folded.
    /// The text is folded here, on both sides of the comparison, so a curly
    /// apostrophe in a transcript is found by a straight one in the query.
    private static func contains(_ text: String, _ needle: String) -> Bool {
        foldingApostrophes(text).range(of: needle, options: options) != nil
    }

    private static func foldingApostrophes(_ string: String) -> String {
        guard string.contains(where: apostrophes.contains) else { return string }
        return String(string.map { apostrophes.contains($0) ? "'" : $0 })
    }

    /// Leading and trailing whitespace is never meant: the keyboard adds a space
    /// after an autocompleted word, and that space must not hide a match at the
    /// end of a transcript.
    private static func normalized(_ query: String) -> String {
        foldingApostrophes(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
