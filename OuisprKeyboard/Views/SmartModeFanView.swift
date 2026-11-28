// OuisprKeyboard/Views/SmartModeFanView.swift
// The long-press Smart Mode fan (issue #79).
import SwiftUI
import OuisprCore

/// The vertical fan of modes that replaces the keys while the mic is held.
///
/// ### It handles no touches at all
///
/// The gesture belongs to the mic pill in the toolbar — the finger went down there,
/// and a single `DragGesture` tracks it from the long-press to the release. So this
/// view is purely a drawing of somebody else's state: `allowsHitTesting(false)` at
/// the bottom is load-bearing, not defensive. A row that accepted a touch would take
/// it from the gesture recogniser mid-drag and the release would land nowhere.
///
/// ### The geometry is not in this file
///
/// Row height and the y-to-row mapping live in `SmartModeFanLayout`, in OuisprCore,
/// because the keyboard target has no test bundle and that arithmetic is what
/// settled #79's fan-capacity contradiction. This view reads the numbers; it does
/// not decide them.
struct SmartModeFanView: View {

    let state: SmartModeFanState

    /// Space below the toolbar, measured by the caller.
    let availableHeight: CGFloat

    private var showsReason: Bool { state.unavailableReason != nil }

    private var rowHeight: CGFloat {
        SmartModeFanLayout.rowHeight(
            availableHeight: availableHeight,
            entryCount: state.entries.count,
            showsReason: showsReason
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.entries.enumerated()), id: \.element.id) { index, entry in
                if case .pro = entry {
                    proRow(isHighlighted: index == state.highlightedIndex)
                } else {
                    row(entry, isHighlighted: index == state.highlightedIndex)
                }
            }

            if let reason = state.unavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    // The sentence must not truncate: it is the whole of what the user
                    // is being told, and half of it is worse than none. It gives up
                    // size on a narrow screen instead, the same trade the #315 notice
                    // makes in the toolbar.
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: SmartModeFanLayout.reasonHeight)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(panel)
        // See the type's doc comment. This is what keeps the drag on the mic's
        // recogniser instead of letting a row swallow it.
        .allowsHitTesting(false)
    }

    // MARK: - Rows

    /// One row, as the app's mode menu draws it (lot 1.4): the mode's glyph in ink, its
    /// name at 17 pt with one line under it at 13 pt saying what it does, and the tag or
    /// the tick at the trailing edge.
    ///
    /// ### Why the rows sit on one panel and the highlight is neutral
    ///
    /// The fan stands in for the keys, on a translucent keyboard, so the rows need a
    /// surface (captures of 2026-08-24: text floating on the host app's text). Until
    /// lot 1.4 each row had its own glass capsule and the row under the finger turned
    /// blue. Alex's bench chose the app's menu instead: one rounded panel, rows without
    /// their own shapes, and a neutral grey under the finger. The panel's corners are
    /// rounded like the menu's, which is what the 2026-08 hard-edged sheet lacked.
    ///
    /// The thumb covers the row it is choosing, so the highlight spans the whole row:
    /// its edges are what stays visible.
    ///
    /// A disabled row still draws its name and icon rather than being hidden. The user
    /// is entitled to see what the feature is before being told they cannot have it
    /// here — the same honesty the paywall's capability filter applies (#79), one
    /// surface earlier.
    private func row(_ entry: SmartModeFanEntry, isHighlighted: Bool) -> some View {
        // `modesAreArmable` and not `showsReason`: the non-subscriber's fan refuses
        // every mode and shows no sentence, so inferring one from the other would draw
        // its rows enabled (#404).
        let isEnabled = entry.smartMode == nil || state.modesAreArmable
        return HStack(spacing: 14) {
            Image(systemName: icon(entry))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ouisprInk)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name(entry))
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                if let summary = summary(entry) {
                    Text(summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            // The summary gives way on a narrow screen before the name does.
            .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            marker(for: entry)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(highlight(isHighlighted))
        .opacity(isEnabled ? 1 : 0.4)
    }

    /// What a row says about itself when the finger is not on it (#423, #404).
    ///
    /// Three tags, never two at once, and the precedence lives in
    /// `SmartModeFanLayout.tag(for:...)` — in OuisprCore, because this target has no
    /// test bundle and the rule has enough branches to be worth checking.
    ///
    /// - **The check** goes on the row that will actually run. "Armed" and "in force"
    ///   stopped being the same thing the moment a mode could stay armed and not run:
    ///   greying a mode row says *you cannot pick this*, not *the thing you already
    ///   picked will not happen*, and only the second was true when the maintainer hit
    ///   #423.
    /// - **`INACTIF`** goes on the armed row when it is not the one running. The choice
    ///   survived — `resolveArmedMode` keeps it deliberately — and the tag says so
    ///   without claiming it is active.
    /// - **`PRO`** goes on every mode row of a non-subscriber's fan (#404). Verbatim
    ///   and not localised: it is the product's own abbreviation and reads the same in
    ///   both languages, like "Ouispr Pro" beside it.
    @ViewBuilder
    private func marker(for entry: SmartModeFanEntry) -> some View {
        switch state.tag(for: entry) {
        case .effective:
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ouisprInk)
        case .inactive:
            tagCapsule(Text(
                "Off",
                comment: "Marker on the Smart Mode fan row the user armed, when that mode will not run and the dictation goes in as Normal."
            ))
        case .pro:
            tagCapsule(Text(
                "PRO",
                comment: "Tag on a Smart Mode fan row that is behind the Ouispr Pro subscription. Identical in French today, and in the catalog so a future locale can change it."
            ))
        case nil:
            EmptyView()
        }
    }

    /// The pill a word-tag sits in. Muted on purpose: it labels a row the user cannot
    /// choose, and a loud badge on an unreachable row reads as an alarm.
    private func tagCapsule(_ label: Text) -> some View {
        label
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }

    /// The neutral grey under the finger, inset like a menu row's.
    private func highlight(_ isHighlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(isHighlighted ? 0.1 : 0))
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
    }

    /// The one panel behind the rows: the app menu's rounded platter, in the keyboard's
    /// glass.
    private var panel: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.clear)
            .ouisprGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    /// The Ouispr Pro row: the last of the four in a non-subscriber's fan (#404).
    ///
    /// ### Why it is the same size and shape as its neighbours
    ///
    /// It was a single full-height row until 2026-08-29, when the maintainer saw it on
    /// device: *"je ne suis pas fan qu'on ait cette grosse pilule qui prend tout le
    /// clavier"*. The aesthetic objection turned out to be the smallest of three — the
    /// one-row fan also removed the `Normal` row, and with it the only way a
    /// non-subscriber could start a recording from the fan at all. Now the fan is the
    /// same object for everyone, and subscribing un-greys it rather than replacing it.
    ///
    /// So it takes the capsule, the height and the layout of a mode row, and differs
    /// only where it must: the paywall's own gradient, so the Pro signal reads the same
    /// here as on `ToolbarView.proEntry`, and a chevron, because it is the one row that
    /// leaves the keyboard.
    private func proRow(isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))

            Text(
                "Ouispr Pro",
                comment: "The Smart Mode fan row that leaves the keyboard for the paywall. A product name, so identical in French today, and in the catalog so a future locale can change it."
            )
            .font(.system(size: 17, weight: isHighlighted ? .bold : .semibold))
            .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(
            LinearGradient(
                colors: [.ouisprGradientStart, .ouisprGradientEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight)
        .background(highlight(isHighlighted))
    }

    /// The row's name, as the app's menu says it: Normal, Rédigé, Liste, Traduire → EN.
    ///
    /// Normal is named here rather than on the entry: OuisprCore ships no string catalog.
    /// A translation mode gets its verb back (lot 1.4): the fan's rows are now as wide as
    /// the menu's, and « → EN » alone was the 46 pt row's shorthand.
    private func name(_ entry: SmartModeFanEntry) -> String {
        guard let mode = entry.smartMode else {
            return String(
                localized: "Normal",
                comment: "The Smart Mode fan row that clears the armed mode and returns to the free polish."
            )
        }
        guard mode.id.hasPrefix("translate.") else { return mode.localizedDisplayName }
        return String(
            localized: "Translate \(mode.displayName)",
            comment: "Keyboard fan name of a translation Smart Mode; the placeholder is the arrow and target, e.g. « → EN » (lot 1.4)."
        )
    }

    /// The glyph the app's menu uses for the mode (lot 1.3): a paragraph for Normal, a
    /// pen for Rédigé, the catalogue's own glyph otherwise.
    private func icon(_ entry: SmartModeFanEntry) -> String {
        switch entry {
        case .normal: return "text.alignleft"
        case .pro: return "sparkles"
        case .mode(let mode):
            return mode.id == SmartModeCatalogue.structuredIdentifier ? "pencil.line" : mode.icon
        }
    }

    /// What the mode does, in one line, as the app's menu says it. Nil for a mode this
    /// build does not know.
    private func summary(_ entry: SmartModeFanEntry) -> String? {
        switch entry {
        case .pro:
            return nil
        case .normal:
            return String(localized: "Your text, cleaned up", comment: "Under « Normal » in the keyboard's mode list (lot 1.4).")
        case .mode(let mode):
            switch mode.id {
            case SmartModeCatalogue.structuredIdentifier:
                return String(localized: "Polished sentences, ready to send", comment: "Under « Rédigé » in the keyboard's mode list (lot 1.4).")
            case SmartModeCatalogue.notesIdentifier:
                return String(localized: "The key points as a list", comment: "Under « Liste » in the keyboard's mode list (lot 1.4).")
            case SmartModeCatalogue.messageIdentifier:
                return String(localized: "A short, direct message", comment: "Under « Message » in the keyboard's mode list (lot 1.4).")
            case SmartModeCatalogue.summaryIdentifier:
                return String(localized: "The gist in a few lines", comment: "Under « Résumé » in the keyboard's mode list (lot 1.4).")
            case let id where id.hasPrefix("translate."):
                return String(localized: "Translated into the chosen language", comment: "Under a « Traduire » mode in the keyboard's mode list (lot 1.4).")
            default:
                return nil
            }
        }
    }
}
