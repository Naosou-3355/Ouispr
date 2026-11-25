// OuisprCore/Sources/OuisprCore/Subscription/ProWindow.swift
// What the Ouispr Pro window shows, depending on where it was opened from (Pro offer V1, 25 Nov 2026).
import Foundation

/// Where the Ouispr Pro window was opened from.
///
/// WHY it matters: the window is centred on the feature the user just touched
/// (decision of 25 Nov 2026, "Fenêtre centrée sur la fonction"). Opened from the
/// mode menu it leads with the modes; opened from a search past the free window it
/// leads with the history; opened from Settings it shows the four features evenly.
public enum ProWindowEntry: Equatable, Sendable {
    /// The Ouispr Pro row in Settings: nothing in particular was asked for.
    case settings
    /// A Pro feature the user tried to use.
    case feature(ProFeature)
}

/// The order and the emphasis of the window's feature list.
///
/// A pure function of the entry point, so the rule is tested here rather than read
/// off a screenshot: the app target has no test bundle.
public struct ProWindowLayout: Equatable, Sendable {

    /// The feature shown on top in its own block, with its own sentence, or nil when
    /// the window was opened from Settings.
    public let focus: ProFeature?

    /// The features listed in the grouped card, the focused one excluded so it is
    /// never shown twice.
    public let rows: [ProFeature]

    /// The order the four features are listed in, as validated on the Pro bench:
    /// Modes, Learns from you, Unlimited history, Voice messages.
    ///
    /// WHY not `ProFeature.allCases`: that order is the enum's, which older screens
    /// were laid out for (`ProFeature.voiceNotes` says so); the window has its own.
    public static let order: [ProFeature] = [.smartMode, .vocabulary, .history, .voiceNotes]

    public static func layout(for entry: ProWindowEntry) -> ProWindowLayout {
        switch entry {
        case .settings:
            return ProWindowLayout(focus: nil, rows: order)
        case .feature(let feature):
            return ProWindowLayout(focus: feature, rows: order.filter { $0 != feature })
        }
    }
}

extension ProFeature {

    /// The title of the block the window leads with when this feature was touched.
    /// English source string, translated in the app's string catalogue.
    public var focusTitle: String {
        switch self {
        case .smartMode: return "The modes"
        case .history: return "All your history"
        // Not "Ouispr learns from you": that is the window's subtitle, right above.
        case .vocabulary: return "Your vocabulary"
        case .voiceNotes: return "Voice messages"
        }
    }

    /// The sentence under `focusTitle`: what the feature does, in one line.
    ///
    /// The history sentence names the free window (`HistoryAvailability.freeSearchDays`)
    /// so the limit the user just met is stated where it is lifted.
    public var focusLine: String {
        switch self {
        case .smartMode:
            return "Choose the shape before you speak: a polished text, a list of who does what, or a translation."
        case .history:
            return "Free search covers the last 7 days. With Pro, find any dictation, however old."
        case .vocabulary:
            return "Ouispr suggests the words it gets wrong, from your corrections and your dictations. Nothing is added without you."
        case .voiceNotes:
            return "Share a voice message with Ouispr and read it instead of listening to it."
        }
    }
}

/// The reverse trial explained as three dated steps.
///
/// Apple's Human Interface Guidelines for in-app purchase ask apps to "clearly
/// describe how a free trial works". Ouispr's trial is unusual and worth saying
/// plainly: nothing is charged when it ends, the app simply returns to free.
public enum ProTrialTimeline {

    public struct Step: Equatable, Sendable {
        /// Day the step happens on, counted from the start (0 is today).
        public let day: Int
        /// English source strings, translated in the app's catalogue.
        public let title: String
        public let detail: String
    }

    /// Today, the reminder `ProTrial.reminderLeadDays` before the end, and the end.
    ///
    /// The reminder step is only true because the home screen still shows the trial's
    /// last-days card (`ProHomeCard`): the two must change together.
    public static func steps(durationDays: Int = ProTrial.durationDays,
                             reminderLeadDays: Int = ProTrial.reminderLeadDays) -> [Step] {
        [
            Step(day: 0, title: "Today", detail: "All of Pro, free"),
            Step(day: durationDays - reminderLeadDays, title: "Day \(durationDays - reminderLeadDays)",
                 detail: "A reminder in the app"),
            Step(day: durationDays, title: "Day \(durationDays)", detail: "Back to free, nothing charged")
        ]
    }
}
