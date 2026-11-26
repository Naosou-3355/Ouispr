// OuisprApp/Views/DictationCards.swift
// The glass dictation card of Home and the history: its glass, its title, and its date label.
import SwiftUI
import OuisprCore

// MARK: - Card

/// One dictation as a cloud card: its short title in a glass pill, nothing else.
///
/// « Fiche historique et accueil V1 » (Alex, 24 Nov 2026): real glass, a 2-3 word
/// title, 96 pt tall, 30 pt corners. A new dictation's card brings its words in one by
/// one, from blurred to sharp, the rule every dictated text follows.
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
    /// The word-by-word reveal's progress (0 to 1) for the card arriving from the
    /// character; nil, a sharp title, for every other card.
    var reveal: Double?

    init(record: TranscriptionRecord, title: String? = nil, width: CGFloat? = nil, reveal: Double? = nil) {
        self.record = record
        self.reveal = reveal
        let title = title ?? DictationCloud.title(for: record.text)
        self.title = title
        self.width = width ?? CGFloat(DictationCloud.cardWidth(forTitle: title))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        DictationTitleReveal(title: title, reveal: reveal)
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

/// A card's title, on up to two lines: sharp, or coming into focus word by word.
///
/// Only the card arriving from the character reveals its words, once, as it lands
/// (`reveal` animated from 0 to 1 by its flight); every other card, in a row or the
/// history, is sharp from the start (audit of 26 Nov 2026, n°5: a card's words must
/// never stay blurred while it drifts).
///
/// WHY a text renderer and not a view per word: the words keep the exact layout of the
/// plain title the row draws once the card has landed, so the hand-over does not move
/// a letter; and one animated value drives every word, so nothing is left running once
/// it reaches 1 (no per-word animation to interrupt or to keep alive).
private struct DictationTitleReveal: View {
    let title: String
    /// The word-by-word reveal's progress, 0 to 1; nil for a sharp title.
    let reveal: Double?

    var body: some View {
        styled(titleText)
    }

    private func styled(_ text: Text) -> some View {
        text
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.ouisprTextPrimary)
            .modifier(WordRevealEffect(reveal: reveal, plan: WordRevealPlan(text: title)))
    }

    /// The title, each word tagged with its rank for the renderer.
    private var titleText: Text {
        guard reveal != nil, #available(iOS 18, *) else { return Text(verbatim: title) }
        let words = title.split(separator: " ").map(String.init)
        var text = Text(verbatim: "")
        for (rank, word) in words.enumerated() {
            let piece = Text(verbatim: word).customAttribute(WordRank(rank: rank))
            text = rank == 0 ? piece : text + Text(verbatim: " ") + piece
        }
        return text
    }
}

/// The reveal applied to a title: the renderer on iOS 18, a fade before it.
private struct WordRevealEffect: ViewModifier {
    let reveal: Double?
    let plan: WordRevealPlan

    func body(content: Content) -> some View {
        // The renderer stays in place at 1 as well: removed at the end value, it would
        // leave the animation nothing to interpolate, and the words would jump to sharp.
        // At 1 it draws every word plainly, and the arriving card is gone soon after.
        if let reveal {
            if #available(iOS 18, *) {
                content.textRenderer(WordRevealRenderer(progress: reveal, plan: plan))
            } else {
                content.opacity(0.25 + 0.75 * reveal)
            }
        } else {
            content
        }
    }
}

/// A word's rank in its title, read by `WordRevealRenderer`.
@available(iOS 18, *)
private struct WordRank: TextAttribute {
    let rank: Int
}

/// Draws each word from a faint blur to sharp, in reading order, on the dictated text's
/// timing (`WordRevealPlan`): `progress` is the share of the whole reveal's time.
@available(iOS 18, *)
private struct WordRevealRenderer: TextRenderer, Animatable {
    var progress: Double
    let plan: WordRevealPlan

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let time = progress * plan.totalDuration
        for line in layout {
            for run in line {
                guard let rank = run[WordRank.self]?.rank else {
                    context.draw(run)
                    continue
                }
                let local = min(1, max(0, (time - plan.delay(forWordAt: rank)) / WordRevealPlan.wordDuration))
                // Ease out, as the dictated text's words do.
                let eased = 1 - (1 - local) * (1 - local)
                var copy = context
                // From a faint blur, never from nothing: a card is never an empty chip.
                copy.opacity = 0.25 + 0.75 * eased
                if eased < 1 { copy.addFilter(.blur(radius: 6 * (1 - eased))) }
                copy.draw(run)
            }
        }
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
