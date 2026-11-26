// OuisprApp/Views/DictationCards.swift
// The glass dictation card of Home and the history: its glass, its title, and its date label.
import SwiftUI
import OuisprCore

// MARK: - Card

/// One dictation as a cloud card: its short title in a glass pill, nothing else.
///
/// « Fiche historique et accueil V1 » (Alex, 24 Nov 2026): real glass, a 2-3 word
/// title, 96 pt tall, 30 pt corners. The words come in one by one, from blurred to
/// sharp, the rule every dictated text follows.
struct DictationCloudCard: View {
    let record: TranscriptionRecord
    let title: String
    let width: CGFloat

    static let height: CGFloat = 96
    static let cornerRadius: CGFloat = 30
    static let gap: CGFloat = 8
    /// The cards' spring, the fiche's « ressort carte » (0.32 s, damping 0.84): a card
    /// landing, moving along its row, opening and closing.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.84)

    /// The drifting cards are drawn in pre-rendered glass (`FauxCardGlass`), Alex's choice
    /// of 26 Nov 2026. Live Liquid Glass stays behind an internal switch, to compare the
    /// two: launch argument `-OuisprLiveGlass YES`.
    static let usesFauxGlass = !UserDefaults.standard.bool(forKey: "OuisprLiveGlass")

    /// Title and width are worked out once by the caller that has them (the drifting
    /// row's layout); a card on its own works them out here.
    init(record: TranscriptionRecord, title: String? = nil, width: CGFloat? = nil) {
        self.record = record
        let title = title ?? DictationCloud.title(for: record.text)
        self.title = title
        self.width = width ?? CGFloat(DictationCloud.cardWidth(forTitle: title))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        DictationTitleReveal(title: title, id: record.id)
            .padding(.horizontal, 18)
            .frame(width: width, height: Self.height)
            .modifier(CardGlass(shape: shape, faux: Self.usesFauxGlass))
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: record.text))
            .accessibilityHint(Text(record.shortDateLabel))
            .accessibilityIdentifier("history.card")
    }
}

/// The card's material: the pre-rendered glass, or Liquid Glass behind the switch.
private struct CardGlass<S: Shape>: ViewModifier {
    let shape: S
    let faux: Bool

    func body(content: Content) -> some View {
        if faux {
            content.background { FauxCardGlassBackground() }
        } else {
            content.ouisprGlass(in: shape)
        }
    }
}

/// A card's title, from blurred to sharp in 0.35 s, on up to two lines.
///
/// WHY the whole title at once and not word by word: in a drifting row the words after
/// the first could stay blurred (audit of 26 Nov 2026, n°5): each word ran its own
/// delayed animation, and a card drawn again by its row before the delays ran out kept
/// the words that had not started. One animation has nothing left to interrupt.
private struct DictationTitleReveal: View {
    let title: String
    let id: UUID

    /// Already shown sharp when this card's title came in before (`RevealedTitles`).
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, id: UUID) {
        self.title = title
        self.id = id
        _shown = State(initialValue: RevealedTitles.seen.contains(id))
    }

    var body: some View {
        Text(verbatim: title)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.ouisprTextPrimary)
            // From a faint blur, never from nothing: a card is never an empty chip.
            .opacity(shown ? 1 : 0.25)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .animation(.easeOut(duration: WordRevealPlan.wordDuration), value: shown)
            .onAppear {
                // Once per card and launch: a card drifting back into view, or drawn
                // again by its row, is not a new dictation.
                RevealedTitles.seen.insert(id)
                shown = true
            }
    }
}

/// The cards whose title has already come in word by word.
@MainActor
enum RevealedTitles {
    fileprivate static var seen = Set<UUID>()

    /// A card whose words must show at once, such as the one flying in from the character.
    static func markSeen(_ id: UUID) { seen.insert(id) }
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
