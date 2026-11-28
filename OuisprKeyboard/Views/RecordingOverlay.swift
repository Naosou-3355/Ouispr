// OuisprKeyboard/Views/RecordingOverlay.swift
import QuartzCore
import SwiftUI
import OuisprCore

/// The listening screen that replaces the keyboard while a dictation runs.
///
/// Lot 1.6 (Alex's bench of 28 Nov 2026, « micro qui se transforme »): when the mic is
/// tapped, its three bars change in place. The two on the right spring into the ✓ that
/// ends the dictation, where the user tapped; the left one flies to the far left, where
/// the ☰ was, and becomes the ✕ that cancels it. Both are bare ink glyphs, no disc. That
/// leaves the centre to one ample ink wave that follows the voice, with a quiet state
/// word under it. When the text is in, the keys come back at once and the mic plays the
/// laughing eyes on its own (`InkBarsMicButton`): nothing here waits for it.
///
/// - .requested: the bars turn into ✕ and ✓ (✓ in full ink but inert until the recording
///   starts), a breathing wave, « J'écoute »
/// - .recording: ✕ and ✓, the wave follows the voice, « J'écoute »
/// - .transcribing / .processing: ✓ greyed, no ✕ (neither stage can be cancelled, #267),
///   a calm travelling wave, « Transcription »
///
/// WHY the top row copies the bar's layout to the point: the overlay replaces the bar in
/// one frame, so the bars it starts from must sit exactly where the mic's were. Then the
/// swap cannot be seen and the morph reads as the mic itself changing.
///
/// WHY it replaces the keyboard: when recording, the keyboard area turns into the
/// listening UI. This prevents accidental key presses during dictation and gives clear
/// feedback that the mic is live.
///
/// WHY the wave is driven by `KeyboardWaveformDriver` and not a `TimelineView`: a
/// `TimelineView` proved fragile inside the keyboard extension after suspension and
/// resume. The driver's display link starts and stops with the overlay, and it already
/// carries the voice's levels; the wave reads them on each of its ticks.
struct RecordingOverlay: View {
    /// The stage to draw — `KeyboardState.displayedDictationStatus`, not the raw
    /// dictation status (#309). The two differ for at most half a second, while a
    /// transcription that returned faster than the eye can read it is held on screen.
    ///
    /// The probes below therefore report what was *drawn*, which is what they are for.
    /// The pipeline's own transitions are logged unchanged by `KeyboardState`, and the
    /// hold itself by its `transcribingHoldArmed` / `transcribingHoldReleased` probes,
    /// so a log still says both what happened and what the user saw.
    let dictationStatus: DictationStatus
    /// Only reported in the probes: the eyes read the driver's smoothed levels.
    let waveformEnergy: [Float]
    /// Passed through to the eyes, which observe it; the overlay does not.
    let waveformDriver: KeyboardWaveformDriver
    let onCancel: () -> Void
    let onStop: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The armed Smart Mode, or nil for Normal (#79).
    ///
    /// **This is the indicator that makes a sticky mode safe.** The mode survives
    /// restarts and can have been armed a week ago; the mic's badge names it, but by
    /// the time the overlay is up the mic is gone and the badge with it. Naming it here
    /// means the user reads "List" while speaking, with the cancel button one tap
    /// away — which is the difference between a setting they forgot and a setting that
    /// cost them a dictation.
    var armedSmartMode: SmartMode?

    @State private var instanceID = String(UUID().uuidString.prefix(8))

    var body: some View {
        VStack(spacing: 0) {
            topRow

            // WHY Spacers and no GeometryReader around the whole: on the first frame the
            // hosting view may still be at toolbar height (52 pt) before growing to the
            // keyboard's. Fixed sizes between Spacers are centred from the first frame.
            Spacer(minLength: 0)

            // The frame holds the wave at full voice (about 60 pt each side of its axis at
            // the app's size), so a loud syllable never runs into « J'écoute » below.
            KeyboardInkWave(status: dictationStatus, driver: waveformDriver, scale: isCompactHeight ? 0.42 : 1)
                .frame(height: isCompactHeight ? 52 : 124)

            stateWord
                .padding(.top, 12)
                // Capped so a large text size cannot push the word under the keyboard's
                // edge in landscape.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(GeometryReader { proxy in
            // The overlay's laid-out size, once per overlay (lot 1.5): the proof on a
            // device log that the listening screen had its room, the face included.
            Color.clear.onAppear {
                PersistentLog.log(.diagnosticProbe(
                    component: "RecordingOverlay",
                    instanceID: instanceID,
                    action: "laidOut",
                    details: "size=\(Int(proxy.size.width))x\(Int(proxy.size.height)) status=\(dictationStatus.rawValue) compact=\(isCompactHeight) reduceMotion=\(reduceMotion)"
                ))
            }
        })
        .onAppear {
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "onAppear",
                details: "status=\(dictationStatus.rawValue) energyCount=\(waveformEnergy.count)"
            ))
            PersistentLog.log(.overlayBodyEvaluated(
                status: dictationStatus.rawValue,
                showsOverlay: true,
                energyCount: waveformEnergy.count
            ))
        }
        .onDisappear {
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "onDisappear",
                details: "status=\(dictationStatus.rawValue)"
            ))
        }
        .onChange(of: dictationStatus) { _, newStatus in
            morph()
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "statusChanged",
                details: "newStatus=\(newStatus.rawValue) energyCount=\(waveformEnergy.count)"
            ))
        }
    }

    // MARK: - Pieces

    /// True in iPhone landscape, where the keyboard and its bar are about 222 pt tall:
    /// the wave drops from 64 to 40 pt.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    /// Whether the bars have turned into ✕ and ✓. False only for the first frames of an
    /// overlay that opens on a tap, where it is the mic as the bar drew it.
    @State private var isMorphed = false

    /// How long the start (the mic as the bar drew it) stays on screen before the spring.
    ///
    /// WHY a delay at all (lot 1.7, Alex's iPhone video of the 1.6): setting `isMorphed`
    /// in `onAppear` lands in the same pass that inserts the overlay, so SwiftUI never
    /// draws the start and the screen arrived with ✕ and ✓ already in place. Even the next
    /// main-queue turn can run before Core Animation commits the frame. 50 ms is three
    /// frames at 60 Hz: the start is drawn for certain, and too short to read as a wait.
    private static let morphStartHold: TimeInterval = 0.05
    /// Set by `morph()` when the spring is to play; the task above plays it.
    @State private var morphRequested = false
    /// The glyphs' opacity, which is all that changes under Reduce Motion.
    @State private var glyphOpacity: Double = 1

    /// ✕ where the ☰ was, the armed mode in the middle, ✓ where the mic was.
    ///
    /// The same paddings, height and slot widths as `ToolbarView`'s bar (12 pt sides,
    /// 4 pt top, 52 pt, 56 × 44 slots), so the bars the morph starts from sit exactly on
    /// the mic it replaces.
    private var topRow: some View {
        GeometryReader { proxy in
            // From the ✓'s slot to the ✕'s: the distance the left bar flies.
            let travel = max(0, proxy.size.width - 56)
            ZStack {
                armedModeBadge
                HStack(spacing: 0) {
                    cancelButton(travel: travel)
                    Spacer(minLength: 0)
                    confirmButton
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(height: 52)
        .onAppear(perform: morph)
        // The spring after the start hold. A task, so it is cancelled with the overlay.
        .task(id: morphRequested) {
            guard morphRequested else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.morphStartHold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(InkBarsMicButton.morphSpring) { isMorphed = true }
        }
    }

    /// Starts the morph, when `ListeningMorph` says this opening plays it: within its
    /// window of a mic tap, in `.requested` or already in `.recording` after the trip to
    /// the app (once per tap there). Otherwise the screen starts as ✕ and ✓.
    private func morph() {
        guard !isMorphed, !morphRequested else { return }
        // The overlay is inserted as soon as the real stage owns the keyboard area, but
        // the stage it draws (`displayedDictationStatus`) can still read `.idle` in that
        // pass: measured on the simulator, 28 Nov 2026, and the reason the 1.6's
        // `.requested` check never played the morph. Decide on the first real stage, from
        // `onChange`; meanwhile the bars stay as the mic drew them.
        guard dictationStatus != .idle else { return }
        let plays = !reduceMotion && ListeningMorph.claimMorph(status: dictationStatus)
        PersistentLog.log(.diagnosticProbe(
            component: "RecordingOverlay",
            instanceID: instanceID,
            action: "morph",
            details: "plays=\(plays) status=\(dictationStatus.rawValue) reduceMotion=\(reduceMotion)"
        ))
        if plays {
            morphRequested = true
        } else {
            isMorphed = true
            if reduceMotion {
                // Reduce Motion: no stroke moves, the glyphs fade in.
                glyphOpacity = 0
                // Next run-loop turn, or the fade starts from the 1 already drawn.
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) { glyphOpacity = 1 }
                }
            }
        }
    }

    /// The ✕: the mic's left bar, which flies from the mic's slot to this one and splits
    /// into the cross. Shown while a cancel can do something; hidden, its room kept, while
    /// the words are worked out (#267).
    private func cancelButton(travel: CGFloat) -> some View {
        // Also after a failure: if the overlay is still up then, the ✕ is the way out.
        let cancellable = dictationStatus == .requested || dictationStatus == .recording
            || dictationStatus == .failed
        return Button {
            HapticFeedback.recordingStopped()
            onCancel()
        } label: {
            glyph(isMorphed ? InkMicGlyph.cross.strokes : InkMicGlyph.leftBarOnly)
                .offset(x: isMorphed ? 0 : travel)
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.88, pressedOpacity: 0.7))
        .opacity(cancellable ? 1 : 0)
        .disabled(!cancellable)
        .accessibilityHidden(!cancellable)
        .accessibilityLabel(Text("Cancel", comment: "VoiceOver name of the ✕ that cancels a dictation on the keyboard's listening screen (lot 1.4)."))
    }

    /// The ✓: the mic's centre and right bars, which turn into the tick in place. It ends
    /// the dictation and writes it.
    ///
    /// Greyed only while the words are worked out, a stage that lasts and is labelled
    /// « Transcription ». In `.requested`, which lasts about 100 ms, it stays in full ink:
    /// a grey that flashed for 100 ms read as a flicker on Alex's iPhone (NN/g: a state too
    /// short to read is noise, not status).
    ///
    /// A tap in `.requested` is ignored, with no press effect (disabled), rather than
    /// remembered: a remembered stop would end a recording the moment it began, keeping
    /// nothing, and turn a hesitant double tap into a lost dictation. Ignored, the user
    /// sees the wave answer and taps again.
    private var confirmButton: some View {
        let confirmable = dictationStatus == .recording
        let greyed = dictationStatus == .transcribing || dictationStatus == .processing
        return Button {
            HapticFeedback.recordingStopped()
            onStop()
        } label: {
            glyph(isMorphed ? InkMicGlyph.check.strokes : InkMicGlyph.barsWithoutLeft)
                .opacity(greyed && isMorphed ? 0.35 : 1)
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.88, pressedOpacity: 0.7))
        .disabled(!confirmable)
        .accessibilityLabel(Text("Confirm", comment: "VoiceOver name of the ✓ that ends a dictation and writes it, on the keyboard's listening screen: « Valider » (lot 1.5)."))
    }

    /// One bare ink glyph in the mic's 26 pt box, centred in a 56 × 44 target (Apple's
    /// 44 pt minimum), the mic's own slot.
    private func glyph(_ strokes: [InkStroke]) -> some View {
        InkStrokesShape(strokes)
            .fill(Color.ouisprInk)
            .frame(width: 26, height: 26)
            .opacity(glyphOpacity)
            .frame(width: 56, height: 44)
            // A keyboard extension delivers no touch on fully transparent pixels: without
            // this fill only the glyph's strokes would answer.
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
    }

    /// One word under the wave, 13 pt in the quiet grey. It holds the room of the longer
    /// word, so the wave above never moves when it changes, and it says nothing at the end.
    private var stateWord: some View {
        ZStack {
            Text("Listening", comment: "One word under the eyes on the keyboard's listening screen, while it listens: « J'écoute » (lot 1.4).").hidden()
            Text("Transcribing", comment: "One word under the eyes on the keyboard's listening screen, while the words are worked out: « Transcription » (lot 1.4).").hidden()
            switch dictationStatus {
            case .requested, .recording:
                Text("Listening", comment: "One word under the eyes on the keyboard's listening screen, while it listens: « J'écoute » (lot 1.4).")
            case .transcribing, .processing:
                Text("Transcribing", comment: "One word under the eyes on the keyboard's listening screen, while the words are worked out: « Transcription » (lot 1.4).")
            case .idle, .ready, .failed:
                EmptyView()
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.ouisprTextTertiary)
        .lineLimit(1)
    }

    /// The armed mode's name (#79). Renders nothing for Normal: an "off" state announced
    /// on every dictation is noise, and the absence is already unambiguous.
    @ViewBuilder
    private var armedModeBadge: some View {
        if let armedSmartMode {
            HStack(spacing: 5) {
                Image(systemName: armedSmartMode.icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(armedSmartMode.localizedDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.ouisprAccentText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.ouisprAccent.opacity(0.14)))
        } else {
            Color.clear
        }
    }
}

// MARK: - Wave

/// The listening wave in the centre: the app's own (lot 1.8, Alex: « trop différente de
/// celle de l'app »). One `InkCharacterDriver`, the same code as the app's character,
/// in `.listening` while recording and `.working` while the words are worked out, fed
/// the same voice level as the app's (`DictationLevels.recentPeak`: the peak of the last
/// four energy buckets). So the wave is the app's at the app's size, 8 pt thick and about
/// 108 pt wide, its three middle ondulations rising one by one with the voice.
///
/// A filled `Shape` in flat ink, never a `Canvas` with a gradient: the 1.4 eyes, drawn
/// that way, did not show on Alex's iPhone while the simulator drew them. So the logo's
/// left / centre / right shading the app gives the wave is the one difference left.
///
/// Redrawn on each tick of the driver's display link, which runs from the tap to the end
/// of the transcription and stops otherwise. Reduce Motion shows the wave still.
private struct KeyboardInkWave: View {
    let status: DictationStatus
    @ObservedObject var driver: KeyboardWaveformDriver
    /// 1 is the app's size; less in a compact height (landscape).
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The character's state between frames: one per process, since one wave is on screen
    /// at a time, and a reference, so moving it while the body is evaluated does not
    /// invalidate the view (the driver's tick is what redraws). Static rather than
    /// `@State` so the overlay's frequent re-initialisations allocate nothing; replaced
    /// by a fresh one each time the wave appears.
    @MainActor private static let holder = InkDriverHolder()

    var body: some View {
        // Read so that each tick of the display link redraws the wave.
        _ = driver.renderTick
        let frame = Self.holder.driver.frame(
            at: CACurrentMediaTime(),
            mood: mood,
            voiceLevel: status == .recording ? voiceLevel : 0,
            reduceMotion: reduceMotion,
            advancing: !reduceMotion
        )
        return InkFrameShape(frame, scale: scale)
            .fill(Color.ouisprInk)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { Self.holder.driver = InkCharacterDriver(settledIn: .listening) }
    }

    private var mood: ParticleSphereMood {
        switch status {
        case .transcribing, .processing:
            return .working
        case .recording, .idle, .requested, .ready, .failed:
            return .listening
        }
    }

    /// The voice's level, 0 to 1, as the app reads it: the loudest of the last four
    /// levels. A level that is not a number reads as silence.
    private var voiceLevel: Double {
        let peak = Double(driver.displayLevels.suffix(4).max() ?? 0)
        return peak.isFinite ? min(1, max(0, peak)) : 0
    }
}

/// Holds the keyboard wave's driver between frames.
private final class InkDriverHolder {
    var driver = InkCharacterDriver(settledIn: .listening)
}
