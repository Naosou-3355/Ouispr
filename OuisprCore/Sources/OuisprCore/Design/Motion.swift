#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/Motion.swift
// The app's motion scale: three durations and two springs.
import SwiftUI

/// Every one-shot animation in the app picks from this scale.
///
/// WHY a scale: the audit of 22 Nov 2026 counted about twenty durations and ten
/// springs for the same kinds of change (finding 12), so two fades on one screen could
/// run at 0.25 and 0.35 s. A small scale keeps one rhythm across the app and makes a
/// change of feel one edit.
///
/// Loops and timed scene choreography (onboarding scenes, the swipe-back hand) keep
/// their own timings: they are drawings with a clock, not transitions.
///
/// Springs follow Apple's model (WWDC23, "Animate with springs"): a duration and a
/// bounce, with the bounce kept well under the 0.4 Apple cautions against.
public enum Motion {
    /// Feedback on a control, or a small element appearing or leaving.
    public static let quick: Double = 0.15
    /// The default: content changing in place, a stage, a fade between two states.
    public static let standard: Double = 0.25
    /// A screen-sized change: a screen or a scene step entering or leaving.
    public static let emphasized: Double = 0.4

    /// Interactive and interruptible changes: a toggle, a picked option, a ring
    /// opening. A spring keeps its velocity when it is retargeted mid-flight.
    public static let snappy = Animation.spring(duration: 0.3, bounce: 0.15)
    /// Something arriving with a little life: a screen's or a card's entrance.
    public static let gentle = Animation.spring(duration: 0.45, bounce: 0.1)
}
#endif
