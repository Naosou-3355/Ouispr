// OuisprApp/Views/SwipeBackOverlayView.swift
// The screen a dictation started from the keyboard shows while Ouispr holds the microphone.
import SwiftUI
import OuisprCore

/// What the user sees for the moment Ouispr is in front during a dictation started from
/// the keyboard, before it sends them back to their app (lot 1.8).
///
/// WHY this shape (Alex, 28 Nov 2026: « le même design et les mêmes standards que
/// l'application »): the night-blue gradient, the iPhone mockup, the blue dot and the hand
/// were the last screen in the old look, and they taught a gesture the user now almost
/// never needs, since `HostReturnNavigator` sends them back by itself.
/// - The app's own backdrop and ink character, in `.listening` and fed by the voice, as
///   on the app's dictation screen (`RecordingView`): the screen is the dictation, seen
///   from Ouispr. Apple HIG, *Feedback*, and NN/g's first heuristic (visibility of system
///   status): the moving ink says the microphone is live better than a title alone.
/// - Nothing to read at first. The return normally happens within a second, and HIG
///   *Launching* asks for a screen that does not compete with the content coming next.
///   The sentence on why Ouispr had to open appears only if the user is still here after
///   a second; the gesture line only once every automatic way back has failed.
/// - Room for both is reserved from the start (their opacity changes, never the layout),
///   so nothing jumps when they appear. No looping animation: HIG *Motion* (motion that
///   serves no purpose distracts), and Reduce Motion shows the same screen, still.
struct SwipeBackOverlayView: View {
    /// The cold start's audio session is recovering from an audio server reset, and the
    /// return to the host app is held for it (#853). That can take about three seconds, so
    /// the title says the microphone is being prepared rather than that dictation runs.
    var isPreparingMicrophone = false
    /// The voice level, read by the character itself so the rest of the screen does not
    /// redraw at the meter's rate.
    @ObservedObject var levels: DictationLevels

    @ObservedObject private var progress = HostReturnProgress.shared
    @State private var showsExplanation = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the user is on this screen before the sentence on why appears. The return
    /// usually lands sooner, so most people never read it.
    static let explanationDelay: Duration = .seconds(1)

    var body: some View {
        ZStack {
            OuisprBackdrop()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                OverlayCharacter(levels: levels, preparing: isPreparingMicrophone)
                    .frame(width: 200, height: 200)
                    .accessibilityHidden(true)

                Text(isPreparingMicrophone ? preparingMicrophoneTitle : listeningTitle)
                    .font(.ouisprHeading)
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("swipeback.title")

                Text("swipeback_empathy_text")
                    .font(.ouisprBody)
                    .foregroundStyle(Color.ouisprTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .opacity(showsExplanation ? 1 : 0)
                    .accessibilityHidden(!showsExplanation)
                    .accessibilityIdentifier("swipeback.explanation")

                Spacer(minLength: 24)

                Label(gestureHint, systemImage: "arrow.right")
                    .font(.ouisprStageLabel)
                    .foregroundStyle(Color.ouisprTextSecondary)
                    .multilineTextAlignment(.center)
                    .opacity(progress.needsManualReturn ? 1 : 0)
                    .accessibilityHidden(!progress.needsManualReturn)
                    .accessibilityIdentifier("swipeback.gesture")
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.standard), value: showsExplanation)
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.standard), value: progress.needsManualReturn)
        .task {
            try? await Task.sleep(for: Self.explanationDelay)
            guard !Task.isCancelled else { return }
            showsExplanation = true
        }
        .accessibilityIdentifier("swipeback.screen")
    }

    private var listeningTitle: String {
        String(localized: "I'm listening",
               comment: "Title of the screen Ouispr shows for a moment while a dictation started from the keyboard begins, before it returns to the user's app.")
    }

    private var preparingMicrophoneTitle: String {
        String(localized: "Preparing the microphone…",
               comment: "Swipe-back overlay title while a cold start waits for iOS to bring the audio system back, which can take about three seconds; replaces 'Dictation in progress' until recording starts (issue #853).")
    }

    private var gestureHint: String {
        String(localized: "Swipe right along the bottom edge to go back",
               comment: "One line shown only when Ouispr could not return to the user's app by itself: the iOS gesture that switches back to the previous app.")
    }
}

/// The ink character, reading the voice level itself (as `RecordingView`'s sphere does).
private struct OverlayCharacter: View {
    @ObservedObject var levels: DictationLevels
    let preparing: Bool

    var body: some View {
        InkCharacterView(
            mood: preparing ? .working : .listening,
            voiceLevel: preparing ? 0 : levels.recentPeak,
            startsInMood: true
        )
    }
}

// MARK: - Previews

#Preview("Light") {
    SwipeBackOverlayView(levels: DictationLevels())
}

#Preview("Dark") {
    SwipeBackOverlayView(levels: DictationLevels())
        .preferredColorScheme(.dark)
}
