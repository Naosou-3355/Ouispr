// OuisprApp/Views/HomeModeMenu.swift
// Home's mode button: a glass capsule under the character, « Mode Normal ⌄ », opening the
// system menu.
import SwiftUI
import OuisprCore

// MARK: - Button and menu

/// The mode of the next dictation, said under the character and chosen there
/// (« Banc Ouispr épuré », Alex, 27 Nov 2026, « Le nom sous le personnage »): the glyph,
/// the name and a small chevron are one button, and a tap opens iOS's own menu.
///
/// It replaces the glass circle at the top left and the glass menu it stretched into.
/// The mode was said twice, by the circle's glyph and by the line under « Prêt à
/// dicter »; it is now said once, where the eye already is (Apple HIG, Pop-up buttons:
/// the button shows the current choice).
///
/// LOT 1.3 (Alex, 27 Nov 2026: « ○ Aucun ⌄ ne veut rien dire »): no mode is « Normal »
/// now, the button says « Mode » before the name and sits in a glass capsule, and the menu
/// has a title and a line under each mode saying what it does — the pattern of ChatGPT's
/// and Claude's model pickers and of Apple's pull-down buttons (HIG, Pull-down buttons:
/// a title, an icon and a short description per item).
///
/// The menu: Normal, then the pinned modes, then the Ouispr Pro row for a non-subscriber —
/// the keyboard fan's rows (`SmartModeHomePicker`) — then the default mode and the
/// transcription style as submenus.
///
/// WHY the default is a submenu and no longer a long press on a row: the system menu
/// gives its rows a tap and nothing else. A submenu is the system's way to set a second
/// value from the same menu, and it is one more tap, not a hidden gesture.
struct HomeModeMenu: View {
    /// The rows, resolved by Home when it last read the App Group.
    let picker: SmartModeHomePicker
    /// The mode the next dictation runs, the button's label.
    let mode: SmartMode?
    let defaultIdentifier: String?
    let onChoose: (SmartModeFanEntry) -> Void
    let onSetDefault: (SmartModeFanEntry) -> Void

    @AppStorage(SharedKeys.transcriptionStyle, store: UserDefaults(suiteName: AppGroup.identifier))
    private var transcriptionStyle: TranscriptionStyle = .defaultStyle

    var body: some View {
        Menu {
            // The first section's header is the menu's title. Under it, when modes cannot
            // run, the reason, ahead of the rows it greys out.
            Section {
                if let reason = picker.unavailableReason {
                    Text(verbatim: HomeSmartModeCopy.reasonText(reason))
                }
                ForEach(picker.entries) { entry in
                    row(entry)
                }
            } header: {
                Text("Mode for the next dictation", comment: "Title of Home's mode menu (lot 1.3).")
            }

            // At the menu's foot: the default the app returns to after each dictation,
            // and the transcription style, which applies to every dictation.
            Section {
                if let choices = defaultChoices {
                    Picker(selection: defaultSelection(in: choices)) {
                        ForEach(choices) { entry in
                            Text(verbatim: HomeSmartModeCopy.shortName(of: entry)).tag(entry.id)
                        }
                    } label: {
                        Label("Default mode", systemImage: "pin")
                    }
                    .pickerStyle(.menu)
                }
                Picker(selection: $transcriptionStyle) {
                    ForEach(TranscriptionStyle.allCases, id: \.self) { style in
                        Text(TranscriptionStylePicker.title(for: style)).tag(style)
                    }
                } label: {
                    Label("Transcription style", systemImage: "textformat")
                }
                .pickerStyle(.menu)
            }
        } label: {
            label
        }
        .menuOrder(.fixed)
        .accessibilityIdentifier("home.mode")
    }

    /// « [glyph] Mode Normal ⌄ » in a glass capsule: the mode's glyph, « Mode » in the
    /// secondary ink, the name in the primary one, a small chevron.
    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: HomeSmartModeCopy.icon(of: mode))
                .foregroundStyle(Color.ouisprAccentText)
            // One sentence, so a language can put the name first; the name in the primary
            // ink, the rest in the secondary one.
            Text(
                "Mode \(Text(verbatim: HomeSmartModeCopy.name(of: mode)).foregroundStyle(Color.ouisprTextPrimary))",
                comment: "Home's mode button. The placeholder is the mode's name: « Mode Normal » (lot 1.3)."
            )
            .foregroundStyle(Color.ouisprTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ouisprTextTertiary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        // Apple's 44 pt minimum touch target (HIG, Accessibility).
        .frame(minHeight: 44)
        .ouisprGlassBar()
        .contentShape(Capsule())
        // On the label, not on the `Menu`: set there, VoiceOver read the button with no
        // name at all (measured on iOS 26.3, 27 Nov 2026).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Dictation mode"))
        .accessibilityValue(Text(HomeSmartModeCopy.name(of: mode)))
    }

    private func row(_ entry: SmartModeFanEntry) -> some View {
        let selected = picker.effectiveIdentifier == entry.id
        return Button {
            onChoose(entry)
        } label: {
            // A system menu row reads the label's direct children: the first text is the
            // title, a second text the subtitle, the image the glyph. Inside a `Label` the
            // second text was dropped (measured on iOS 26.3, lot 1.3). The tick replaces the
            // glyph on the mode that runs.
            Text(verbatim: HomeSmartModeCopy.shortName(of: entry))
            // The tag first when there is one (« PRO », « Off »), then what the mode does.
            if let subtitle = subtitle(of: entry) {
                Text(verbatim: subtitle)
            }
            Image(systemName: selected ? "checkmark" : icon(of: entry))
        }
        .disabled(!picker.canChoose(entry))
    }

    private func subtitle(of entry: SmartModeFanEntry) -> String? {
        let parts = [HomeSmartModeCopy.tagLabel(picker.tag(for: entry)), HomeSmartModeCopy.summary(of: entry)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The rows a default may be: the armable ones, without Ouispr Pro. Nil when there
    /// is nothing to choose between, the same rule as Réglages.
    private var defaultChoices: [SmartModeFanEntry]? {
        guard !picker.offersProUpgrade, picker.modesAreArmable else { return nil }
        let entries = picker.entries.filter { $0 != .pro }
        return entries.count > 1 ? entries : nil
    }

    private func defaultSelection(in choices: [SmartModeFanEntry]) -> Binding<String> {
        Binding(
            get: {
                // A default since unpinned reads as Normal, as in Réglages.
                let id = defaultIdentifier ?? SmartModeFanEntry.normal.id
                return choices.contains { $0.id == id } ? id : SmartModeFanEntry.normal.id
            },
            set: { id in
                guard let entry = choices.first(where: { $0.id == id }) else { return }
                onSetDefault(entry)
            }
        )
    }

    private func icon(of entry: SmartModeFanEntry) -> String {
        switch entry {
        case .normal: return HomeSmartModeCopy.icon(of: nil)
        case .pro: return "sparkles"
        case .mode(let mode): return HomeSmartModeCopy.icon(of: mode)
        }
    }
}

// MARK: - Copy

/// The words the mode button, its menu and the mic's VoiceOver value share.
enum HomeSmartModeCopy {

    /// A mode's name as Home and Réglages show it: « Rédigé », « Liste »,
    /// « Traduire → EN », or « Normal » for no mode (« Aucun » until lot 1.3: it named
    /// an absence, Normal names what the dictation does, and is the keyboard's word).
    ///
    /// Not the fan's names: the keyboard's 46 pt rows keep « → EN » and « Normal »,
    /// while a menu row has the width for a verb (validated sheet, 25 Nov 2026). Only
    /// the display changes; the stored identifiers do not.
    static func name(of mode: SmartMode?) -> String {
        mode.map(SmartModeListView.listName(for:))
            ?? String(
                localized: "Normal",
                comment: "The Smart Mode fan row that clears the armed mode and returns to the free polish. Same text as the keyboard's (#679)."
            )
    }

    /// The glyph Home's button and menu show for a mode (lot 1.3). Normal is a plain
    /// paragraph; Rédigé gets a pen rather than the catalogue's paragraph, which Normal
    /// now uses, so no two rows of the menu share a glyph. The keyboard keeps the
    /// catalogue's glyphs.
    static func icon(of mode: SmartMode?) -> String {
        guard let mode else { return "text.alignleft" }
        if mode.id == SmartModeCatalogue.structuredIdentifier { return "pencil.line" }
        return mode.icon
    }

    /// What a mode does, in one line, under its name in the menu (lot 1.3). Nil for a
    /// mode the app does not know (a later build's) and for the Ouispr Pro row.
    static func summary(of entry: SmartModeFanEntry) -> String? {
        switch entry {
        case .pro:
            return nil
        case .normal:
            return String(localized: "Your text, cleaned up", comment: "Under « Normal » in Home's mode menu (lot 1.3).")
        case .mode(let mode):
            switch mode.id {
            case SmartModeCatalogue.structuredIdentifier:
                return String(localized: "Polished sentences, ready to send", comment: "Under « Rédigé » in Home's mode menu (lot 1.3).")
            case SmartModeCatalogue.notesIdentifier:
                return String(localized: "The key points as a list", comment: "Under « Liste » in Home's mode menu (lot 1.3).")
            case SmartModeCatalogue.messageIdentifier:
                return String(localized: "A short, direct message", comment: "Under « Message » in Home's mode menu (lot 1.3).")
            case SmartModeCatalogue.summaryIdentifier:
                return String(localized: "The gist in a few lines", comment: "Under « Résumé » in Home's mode menu (lot 1.3).")
            case let id where id.hasPrefix("translate."):
                return String(localized: "Translated into the chosen language", comment: "Under a « Traduire » mode in Home's mode menu (lot 1.3).")
            default:
                return nil
            }
        }
    }

    /// A menu row's name, the Ouispr Pro row included.
    static func shortName(of entry: SmartModeFanEntry) -> String {
        if case .pro = entry { return "Ouispr Pro" }
        return name(of: entry.smartMode)
    }

    /// The word a fan tag says. Nil for the effective row and for no tag.
    static func tagLabel(_ tag: SmartModeFanRowTag?) -> String? {
        switch tag {
        case .inactive:
            return String(
                localized: "Off",
                comment: "Marker on the Smart Mode fan row the user armed, when that mode will not run and the dictation goes in as Normal."
            )
        case .pro:
            return String(
                localized: "PRO",
                comment: "Tag on a Smart Mode fan row that is behind the Ouispr Pro subscription. Identical in French today, and in the catalog so a future locale can change it."
            )
        case .effective, nil:
            return nil
        }
    }

    /// Why no mode may be armed, in the app's words.
    ///
    /// The keyboard's `localizedReason` is the model and cannot be called from here: it
    /// lives in the other target, whose string catalog is its own. Where the app already
    /// has a sentence for the reason it is reused; the rest are the keyboard's sentences.
    /// `.notSubscribed` never reaches here with a sentence to say — the Ouispr Pro sector
    /// is the message, and with nothing on sale the menu does not exist.
    static func reasonText(_ reason: SmartModeUnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return String(localized: "Turn on Apple Intelligence in iOS Settings to use Smart Modes.")
        case .modelNotReady:
            return String(
                localized: "Apple Intelligence is still downloading. Smart Modes will work once it finishes.",
                comment: "Shown in the Smart Mode fan while the on-device model is downloading."
            )
        case .deviceNotEligible:
            return String(localized: "Smart Modes need Apple Intelligence, which this iPhone does not support. Your choices are saved for a device that does.")
        case .osTooOld:
            return String(
                localized: "Smart Modes need iOS 26 or later.",
                comment: "Shown in the Smart Mode fan when the OS predates Apple Foundation Models."
            )
        case .sdkMissing:
            return String(
                localized: "Smart Modes are not available in this build.",
                comment: "Shown in the Smart Mode fan when the build has no FoundationModels SDK."
            )
        case .engineRefusing:
            return String(
                localized: "Apple Intelligence is busy right now. Smart Modes will come back shortly.",
                comment: "Shown in the Smart Mode fan while the process is rate-limited."
            )
        case .switchedOff:
            return String(localized: "Smart Modes are off. Your modes are kept for when you turn them back on.")
        case .notSubscribed, .other:
            return String(
                localized: "Smart Modes are unavailable right now.",
                comment: "Shown in the Smart Mode fan for an unavailability reason this build does not recognise."
            )
        }
    }
}
