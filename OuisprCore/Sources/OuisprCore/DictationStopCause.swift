// OuisprCore/Sources/OuisprCore/DictationStopCause.swift
// What ended a recording, written in the log for every stop (audit of 26 Nov 2026).

import Foundation

/// What ended a recording. The raw value is the log token.
///
/// WHY a closed list rather than a free string: a dictation cut after one second could
/// not be traced on device because nothing said which of the five ways in had fired.
/// Every caller of `stopDictation` now names itself, and a new way in has to add a case.
public enum DictationStopCause: String, Equatable, Sendable, CaseIterable {
    /// The stop button on the app's dictation screen.
    case appButton
    /// The keyboard's stop button, through the Darwin notification.
    case keyboard
    /// The stop button of the Dynamic Island / Live Activity.
    case liveActivity
    /// An audio interruption (a call, Siri, another app) ended the recording.
    case interruption
}
