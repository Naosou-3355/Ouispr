// OuisprApp/Views/DictationRow.swift
// One saved dictation as a flat row: up to two lines of its text, its time on the right.
import SwiftUI
import OuisprCore

/// One saved dictation in Home's recent list and in the history: the text on up to two
/// lines, the time or the date on the right of the first line, nothing else.
///
/// « Banc Ouispr épuré » (Alex, 27 Nov 2026, essai 2 « Deux lignes · 72 pt »): one line
/// made dictations that start alike (« Bonjour… », « Je… ») look the same, two tell them
/// apart. Flat: the row sits on the list's plain surface, glass is for controls only.
///
/// WHY a minimum height and not a fixed one: with a larger text size the row grows
/// instead of cutting its text (Apple HIG, Layout). 72 pt is the 8 pt grid's 12 + two
/// 24 pt lines + 12, at the default size; `@ScaledMetric` grows it with the text.
struct DictationRow: View {
    let record: TranscriptionRecord
    /// False inside a `List`, which pads its rows itself and holds them to
    /// `defaultMinListRowHeight`: the row's own 12 pt and 72 pt would come on top.
    var pads = true

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 72

    var body: some View {
        // First text baselines: the time sits on the first line of the text, not
        // centred against two lines.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: record.text)
                .font(.body)
                .foregroundStyle(Color.ouisprTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                // Marked as a shared file, not a dictation (#620 decision 7).
                if record.source == .sharedFile {
                    Image(systemName: ProFeature.voiceNotes.icon)
                        .accessibilityLabel(Text("Voice note"))
                }
                Text(verbatim: record.shortDateLabel)
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(Color.ouisprTextTertiary)
        }
        .padding(.vertical, pads ? 12 : 0)
        .frame(minHeight: pads ? minHeight : nil, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Date

extension TranscriptionRecord {
    /// Today reads as a time, this year as a day and month, anything older carries the
    /// year. Formatted by Foundation rather than by a string in the catalogue: the order
    /// of the parts and the month's abbreviation are the user's locale's business.
    var shortDateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            return createdAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(createdAt, equalTo: Date(), toGranularity: .year) {
            return createdAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return createdAt.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
