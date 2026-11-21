// OuisprCore/Sources/OuisprCore/FirstDictationStage.swift
// The states of the onboarding's first dictation (#678, #845).
import Foundation

/// What the onboarding's first dictation shows, from what the app can see of the keyboard.
///
/// WHY THESE STATES (#649 decision 1.8, #678, #845): the step teaches the globe long-press with
/// the real keyboards, and the app cannot draw over a system keyboard. So the hint changes
/// with what is on screen, and always sits above the keyboard:
/// 1. the page has focused the field and the keyboard is on its way: no hint yet, since
///    there is no globe to press;
/// 2. the keyboard did not come up, or the user closed it: ask for a tap on the field;
/// 3. Apple's keyboard up: the drawn globe animation, between the field and the keyboard;
/// 4. Ouispr's keyboard up: a banner pointing at the blue mic.
///
/// WHY IN OUISPRCORE: the mapping, the two fallback delays and the completion rule are
/// rules, and the app target has no test bundle.
public enum FirstDictationStage: Equatable, Sendable {
    /// The page has asked for the field's focus and the keyboard is on its way (#845).
    case opening
    /// No keyboard: the auto-focus did not come in time, or the user closed the keyboard.
    case beforeTap
    /// The field is focused and a keyboard other than Ouispr is up (Apple's, or any other).
    case otherKeyboard
    /// The field is focused and the Ouispr keyboard is up.
    case ouisprKeyboard

    /// The stage for a field that is or is not focused, under a keyboard that is or is not
    /// Ouispr's, while the page is or is not still waiting for the focus it asked for.
    ///
    /// WHY FOCUS WINS: an unfocused field has no keyboard, whatever was last up. The input
    /// mode a text view reports after losing focus is the one it had, not one on screen.
    public init(isFieldFocused: Bool, isOuisprKeyboard: Bool, isAwaitingAutoFocus: Bool) {
        if !isFieldFocused {
            self = isAwaitingAutoFocus ? .opening : .beforeTap
        } else if isOuisprKeyboard {
            self = .ouisprKeyboard
        } else {
            self = .otherKeyboard
        }
    }

    /// How long the page waits for the focus it asked for before asking for a tap (#845).
    ///
    /// WHY 1 S: the keyboard slides in within a fraction of a second once the field has
    /// focus. A focus that has not come after a second is one that failed (for example a
    /// request made while the page was still sliding in), and the user would otherwise
    /// face a page with no keyboard and no instruction.
    public static let autoFocusTimeout: TimeInterval = 1

    /// Whether the page stops waiting for its auto-focus and asks for a tap instead.
    public static func autoFocusHasFailed(secondsSinceRequest: TimeInterval, isFieldFocused: Bool) -> Bool {
        !isFieldFocused && secondsSinceRequest >= autoFocusTimeout
    }

    /// How long another keyboard stays up, with Ouispr never seen, before the page offers
    /// "Continue" next to Skip (#845, decided by Pierre on 2026-10-28).
    ///
    /// WHY A WAY OUT: the Ouispr keyboard is detected through a key iOS does not document
    /// (`isOuisprInputMode`). If iOS ever stops answering it, the user is on Ouispr with a
    /// page that never notices.
    public static let continueDelay: TimeInterval = 15

    /// Whether "Continue" shows. `secondsSinceOtherKeyboard` counts from the first time
    /// another keyboard came up on the page, nil if none has yet.
    public static func showsContinue(secondsSinceOtherKeyboard: TimeInterval?, hasSeenOuisprKeyboard: Bool) -> Bool {
        guard !hasSeenOuisprKeyboard, let secondsSinceOtherKeyboard else { return false }
        return secondsSinceOtherKeyboard >= continueDelay
    }

    /// Whether a text input mode identifier is the Ouispr keyboard's.
    ///
    /// A third-party keyboard's input mode identifier is its extension's bundle identifier
    /// (`com.pivi.dictus.keyboard`). The test accepts the Ouispr prefix itself or a bundle
    /// identifier under it (`com.pivi.dictus.` at the start), so another vendor's id that
    /// merely contains the prefix (`com.example.com.pivi.dictus.keyboard`) is not Ouispr.
    /// A nil identifier (the key could not be read) is not Ouispr.
    public static func isOuisprInputMode(identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifier == ouisprBundlePrefix || identifier.hasPrefix(ouisprBundlePrefix + ".")
    }

    /// The prefix every Ouispr bundle identifier shares.
    static let ouisprBundlePrefix = OuisprVariant.current.bundlePrefix

    /// Shortest text that completes the step.
    ///
    /// WHY 3 CHARACTERS: a single keystroke should not count, and a dictation lands several
    /// characters at once. Three still lets a short dictation through ("oui", "non", "ok").
    public static let minimumTextLength = 3

    /// Whether the field's text completes the step.
    ///
    /// WHY "HAS SEEN" AND NOT THE CURRENT STAGE: the rule is the one the page had before
    /// #678. Text typed on Apple's keyboard before switching does not count, but once Ouispr
    /// has been up, the text counts even if the user switches back before it lands.
    ///
    /// WHY TYPED TEXT COUNTS ON EVERY CHIP (#845, decided by Pierre on 2026-10-28): the rule
    /// does not ask how the text got there. Typing with the Ouispr keyboard completes the
    /// step on an A14 or later as it does on an older chip, where the keyboard cannot
    /// dictate (#635).
    public static func completes(text: String, hasSeenOuisprKeyboard: Bool) -> Bool {
        guard hasSeenOuisprKeyboard else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumTextLength
    }
}
