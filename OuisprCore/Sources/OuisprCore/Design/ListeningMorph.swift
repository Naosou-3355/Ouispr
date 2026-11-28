// OuisprCore/Sources/OuisprCore/Design/ListeningMorph.swift
// When the keyboard's listening screen plays the mic's morph into ✕ and ✓ (lot 1.7).
import Foundation

/// Whether the listening screen opens with the mic's three bars turning into ✕ and ✓, or
/// with ✕ and ✓ already in place.
///
/// The morph is there to show where the two buttons came from (Apple HIG, Motion: motion
/// that shows how one thing becomes another). That only means something right after the
/// user tapped the mic. The 1.6 played it only for a screen that opened in `.requested`,
/// and Alex's iPhone video showed why that is not enough: the first tap often opens
/// OuisprApp to start the microphone, and when the user comes back the screen opens
/// already in `.recording`, so the morph never played.
///
/// The rule is now about the tap, not only the stage:
///
/// - It plays only for a screen opening in `.requested` or `.recording`, never under
///   « Transcription ».
/// - It plays within `window` of a mic tap. A screen opening later (the keyboard shown
///   again in the middle of a dictation) starts as ✕ and ✓.
/// - In `.recording` it plays once per tap: the screen the user comes back to after the
///   app plays it, and one rebuilt a second later by a controller reclaim (#260) does
///   not play it again while they speak.
///
/// WHY 8 s and not 3: the trip to the app and back is a cold start plus a swipe, which
/// often takes longer than 3 s.
public enum ListeningMorph {

    /// How long after a mic tap an opening listening screen still plays the morph.
    public static let window: TimeInterval = 8

    private static var defaults: UserDefaults { AppGroup.defaults }

    /// Record a mic tap, at the tap. Synchronized: the keyboard process may not survive
    /// the trip to the app that the tap starts.
    public static func noteMicTap(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: SharedKeys.keyboardMicTappedAt)
        defaults.synchronize()
    }

    /// When the mic was last tapped, or nil if never.
    public static var lastMicTap: Date? {
        date(forKey: SharedKeys.keyboardMicTappedAt)
    }

    /// Whether a listening screen opening now in `status` plays the morph. When it does in
    /// `.recording`, the tap is marked as played, so it plays there once.
    public static func claimMorph(status: DictationStatus, now: Date = Date()) -> Bool {
        let tap = lastMicTap
        let played = date(forKey: SharedKeys.keyboardMorphPlayedForTap)
        guard playsMorph(status: status, lastMicTap: tap, playedForTap: played, now: now) else { return false }
        if status == .recording, let tap {
            defaults.set(tap.timeIntervalSince1970, forKey: SharedKeys.keyboardMorphPlayedForTap)
        }
        return true
    }

    /// The policy alone. A tap in the future (the clock moved back) does not count.
    public static func playsMorph(status: DictationStatus, lastMicTap: Date?, playedForTap: Date?, now: Date) -> Bool {
        guard status == .requested || status == .recording, let lastMicTap else { return false }
        let age = now.timeIntervalSince(lastMicTap)
        guard age >= 0 && age <= window else { return false }
        if status == .recording, let playedForTap, abs(playedForTap.timeIntervalSince(lastMicTap)) < 0.001 {
            return false
        }
        return true
    }

    private static func date(forKey key: String) -> Date? {
        let seconds = defaults.double(forKey: key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }
}
