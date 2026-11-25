// OuisprApp/Views/HomeModeMenu.swift
// Home's mode button (top left), the glass menu it stretches into, and the line under « Prêt à dicter ».
import SwiftUI
import OuisprCore

// MARK: - Button

/// The mode of the next dictation, chosen before speaking (« bouton mode » bench,
/// Alex, 24-25 Nov 2026). A neutral glyph at rest; the armed mode's glyph, in the accent
/// blue, when one is armed.
///
/// It replaces the dial that opened on a long press of the mic (#489): one visible
/// control, where the dial was a gesture nobody could see, and the mic stays a plain
/// ink disc.
struct HomeModeButton: View {
    let mode: SmartMode?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: mode?.icon ?? "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(mode == nil ? Color.ouisprTextPrimary : Color.ouisprAccent)
                .frame(width: 44, height: 44)
                .ouisprGlass(in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Dictation mode")
        .accessibilityValue(Text(HomeSmartModeCopy.spokenName(of: mode)))
        .accessibilityIdentifier("home.mode")
    }
}

// MARK: - Menu

/// The menu the button's glass stretches into: Normal, then the pinned modes, then the
/// Ouispr Pro row for a non-subscriber — the keyboard fan's rows (`SmartModeHomePicker`).
/// A tap chooses and closes; a long press makes the row the default the app returns to
/// after each dictation (`SmartModeDefault`), which a grey line says.
///
/// Anchored on the button's top-left corner, so it grows out of the button rather than
/// appearing over it: a spring of 0.36 s, a fade under Reduce Motion.
///
/// Not here, on purpose: the bench's « Style » selector at the foot (Formel, Décontracté,
/// Très décontracté). The polish has no style to choose yet, and a selector that changes
/// nothing would be a lie.
struct HomeModeMenu: View {
    let picker: SmartModeHomePicker
    let defaultIdentifier: String?
    let onChoose: (SmartModeFanEntry) -> Void
    let onSetDefault: (SmartModeFanEntry) -> Void
    let onClose: () -> Void

    @State private var expanded = false
    /// The row just made the default, for the line that confirms it.
    @State private var confirmedDefault: SmartModeFanEntry?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 300
    static let cornerRadius: CGFloat = 28

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: Motion.quick) : .spring(response: 0.36, dampingFraction: 0.82)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { close(then: onClose) }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(picker.entries) { entry in
                    row(entry)
                }
                footer
            }
            .padding(6)
            .frame(width: Self.width, alignment: .leading)
            .ouisprGlass(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .scaleEffect(expanded || reduceMotion ? 1 : 0.15, anchor: .topLeading)
            .opacity(expanded ? 1 : 0)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { withAnimation(spring) { expanded = true } }
    }

    private func row(_ entry: SmartModeFanEntry) -> some View {
        let selected = picker.effectiveIdentifier == entry.id
        let enabled = picker.canChoose(entry)
        return HStack(spacing: 12) {
            Image(systemName: icon(of: entry))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(selected ? Color.ouisprAccent : Color.ouisprTextSecondary)
                .frame(width: 22)
            Text(verbatim: HomeSmartModeCopy.shortName(of: entry))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ouisprTextPrimary)
            if isDefault(entry) {
                Text("default")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.ouisprAccent)
            }
            Spacer(minLength: 8)
            if let tag = HomeSmartModeCopy.tagLabel(picker.tag(for: entry)) {
                Text(verbatim: tag)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ouisprTextSecondary)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ouisprAccent)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.45)
        .onTapGesture { close { onChoose(entry) } }
        .onLongPressGesture(minimumDuration: 0.5) { setDefault(entry) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { close { onChoose(entry) } }
        .accessibilityAction(named: Text("Set as default")) { setDefault(entry) }
    }

    @ViewBuilder
    private var footer: some View {
        if let reason = picker.unavailableReason {
            Text(verbatim: HomeSmartModeCopy.reasonText(reason))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.ouisprTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
        } else if !picker.offersProUpgrade {
            HStack(spacing: 6) {
                if let confirmedDefault {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ouisprAccent)
                    Text("\(HomeSmartModeCopy.shortName(of: confirmedDefault)) by default",
                         comment: "Confirmation in Home's mode menu after a long press made this mode the default.")
                } else {
                    Text("Long press a mode: default",
                         comment: "Hint at the foot of Home's mode menu: a long press on a row makes it the default mode.")
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Color.ouisprTextSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
        }
    }

    private func icon(of entry: SmartModeFanEntry) -> String {
        switch entry {
        case .normal: return "circle"
        case .pro: return "sparkles"
        case .mode(let mode): return mode.icon
        }
    }

    private func isDefault(_ entry: SmartModeFanEntry) -> Bool {
        switch entry {
        case .normal: return defaultIdentifier == nil
        case .pro: return false
        case .mode(let mode): return defaultIdentifier == mode.id
        }
    }

    private func setDefault(_ entry: SmartModeFanEntry) {
        guard picker.canChoose(entry), entry != .pro else { return }
        HapticFeedback.longPressRecognized()
        onSetDefault(entry)
        withAnimation(.easeOut(duration: Motion.quick)) { confirmedDefault = entry }
    }

    private func close(then action: @escaping () -> Void) {
        withAnimation(spring) {
            expanded = false
        } completion: {
            action()
        }
    }
}

// MARK: - Line under « Prêt à dicter »

/// The armed mode, said under « Prêt à dicter »: its glyph and « Mode Liste », and
/// « · par défaut » when it is the default. No pill around it.
struct HomeModeLine: View {
    let mode: SmartMode
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.ouisprAccent)
            Text("Mode \(HomeSmartModeCopy.name(of: mode))",
                 comment: "Under Ready to dictate on Home: the Smart Mode the next dictation runs.")
                .foregroundStyle(Color.ouisprTextSecondary)
            if isDefault {
                Text("· default", comment: "Appended to the Home mode line when the armed mode is the default one.")
                    .foregroundStyle(Color.ouisprTextTertiary)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Copy

/// The words the mode button, its menu and the mic's VoiceOver value share.
enum HomeSmartModeCopy {

    /// A mode's short name, the fan's: "→ EN", "List", or "Normal".
    static func name(of mode: SmartMode?) -> String {
        mode?.localizedDisplayName
            ?? String(
                localized: "Normal",
                comment: "The Smart Mode fan row that clears the armed mode and returns to the free polish."
            )
    }

    /// A ring sector's name, the Ouispr Pro row included.
    static func shortName(of entry: SmartModeFanEntry) -> String {
        if case .pro = entry { return "Ouispr Pro" }
        return name(of: entry.smartMode)
    }

    /// The name VoiceOver reads: the mode list's, where a translation is "Translate → EN"
    /// rather than an arrow and two letters.
    static func spokenName(of mode: SmartMode?) -> String {
        mode.map(SmartModeListView.listName(for:)) ?? name(of: nil)
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
