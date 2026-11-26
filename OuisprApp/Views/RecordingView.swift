// OuisprApp/Views/RecordingView.swift
// Stable-layout recording screen: the sphere and the controls stay in place, the text appears between them.
import SwiftUI
import OuisprCore

/// Determines the context in which RecordingView is shown.
///
/// WHY a mode enum instead of separate views:
/// The recording experience should feel identical whether the user reaches it
/// from onboarding or from HomeView's "New dictation" button.
/// The only difference is what happens when the user finishes:
/// - onboarding: calls onComplete to advance onboarding
/// - standalone: user taps mic again for new recording, or X to dismiss
enum RecordingMode {
    case onboarding
    case standalone
}

/// Stable-layout recording screen: a stage label, the sphere, the text, the controls.
///
/// WHY stable layout instead of state-driven visibility:
/// Elements appearing/disappearing causes jarring layout shifts. The label, the sphere
/// and the control row keep their place across all states — only what they show changes:
/// - Idle: resting sphere, mic
/// - Recording: "Listening", the sphere follows the voice, cancel / stop
/// - Transcribing, processing: "Cleaning up", the sphere breathes, cancel
/// - Result: "Finished", calm sphere, the text comes into focus word by word,
///   copy / mic / share
///
/// Design V2 (20 Nov 2026). The sphere replaces the waveform this screen used to draw:
/// it is the same object as on Home, so starting a dictation changes what the sphere
/// does, not what is on screen.
///
/// WHAT IS NOT HERE YET, on purpose: the text does not appear while the user speaks
/// (the engines hand over one text at the end), and the screen cannot show the raw
/// text next to the cleaned one (the coordinator publishes only the final text).
struct RecordingView: View {
    let mode: RecordingMode
    var onComplete: (() -> Void)?

    @EnvironmentObject var coordinator: DictationCoordinator

    /// Raises the model preparation screen when a tap arrives during a load (#484).
    /// A no-op outside `MainTabView`, which is the only view that owns that screen.
    @Environment(\.presentModelPreparation) private var presentModelPreparation

    @State private var transcriptionResult: String?
    @State private var showResult = false
    @State private var showError = false
    @State private var errorMessage: String?
    /// Brief "Copié !" feedback when user taps the transcription result.
    @State private var showCopiedFeedback = false
    /// Two-step dismissal: animate out first, then reset coordinator status.
    @State private var isDismissing = false
    /// The screen's content on its way out, which goes faster than the sphere, so the
    /// error or the result does not linger over Home's text.
    @State private var contentLeaving = false
    /// Home's character frame as it was when this screen came up. Home lays itself out
    /// again behind this screen as soon as a result exists (its « last transcription »
    /// card appears), which moved its character about 50 pt up; following it live made
    /// this whole screen jump as the text appeared (Alex's video, 25 Nov 2026). Only the
    /// way out follows Home's new spot, so the hand-over back still lands on it.
    @State private var pinnedHomeFrame: CGRect?
    /// « Terminé » is said once the last word has come into focus, then leaves (Alex's
    /// « Murmure », 25 Nov 2026; audit of 26 Nov 2026).
    @State private var finishedShown = false
    @State private var finishedFaded = false
    /// The character's last step over a result: the drop and its laughing eyes, then the
    /// resting face (audit of 26 Nov 2026: the wave used to stay frozen under the text).
    @State private var resultRested = false
    /// The stage words come in only once Home's « Prêt à dicter », drawn on the same
    /// line, has gone: the two read over each other for a moment (Beta 45 feedback).
    @State private var stageLabelShown = false

    /// The stage this screen draws, which trails `coordinator.status` by up to
    /// `TranscribingStageHold.minimumDisplayDuration` (#309).
    ///
    /// WHY this screen and not only the keyboard overlay: the two share one visual
    /// vocabulary, and someone dictating inside OuisprApp waits on this screen. Fixing
    /// the flash on one surface and not the other would make them disagree about what
    /// the phone is doing within the same second.
    @State private var displayedStatus: DictationStatus = .idle

    /// The rule. Pure and tested in OuisprCore; the timer below is this surface's.
    @State private var hold = TranscribingStageHold()

    /// Fires when a held stage becomes drawable. At most one is ever in flight.
    @State private var holdTask: Task<Void, Never>?

    /// Where Home's mic is on screen, which the button below starts from and goes back
    /// to (#788).
    @ObservedObject private var micAnchor = PrimaryMicAnchor.shared

    /// Where Home's sphere is, which this screen carries: its sphere flies from there to
    /// its own spot on the way in and back on the way out (audit of 22 Nov 2026).
    @ObservedObject private var homeSphere = HomeSphereAnchor.shared

    /// False on the first frame, then true for as long as the screen is up. What the
    /// way in animates from.
    @State private var appeared = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The way in: the sphere moves to its spot and the rest of the screen fades in.
    /// A spring with a hint of bounce, so the sphere settles rather than stops.
    private static let enterAnimation = Motion.gentle

    /// The content's way out: quicker than the sphere's, so nothing of this screen is
    /// still readable over Home's text (audit, 22 Nov 2026).
    private static let contentExitAnimation = Animation.easeOut(duration: Motion.quick)

    /// The way out. A timing curve and not a spring: the hand-over to Home's sphere
    /// happens when it ends, and a spring's "logically complete" leaves the sphere a
    /// few points short of Home's spot, which would show as a jump.
    private static let exitAnimation = Animation.timingCurve(0.3, 0, 0.2, 1, duration: Motion.emphasized)

    /// A change of stage: the controls, the stage label and the error.
    private static let stageAnimation = Animation.smooth(duration: Motion.standard)

    /// The top row with its padding: the close button's 44 pt and 8 pt above it.
    private static let topRowHeight: CGFloat = 52

    /// From the bottom of Home's character square to the top of its heading. Home lays
    /// the square out at three quarters of its height, so an eighth of it hangs below the
    /// layout, and its stack's spacing is 16 pt (`HomeView.character`).
    private static func homeHeadingGap(characterSide: CGFloat) -> CGFloat {
        16 - characterSide / 8
    }

    /// Height of the slot the mic / stop button is centred in.
    private static let micSlotHeight: CGFloat = 100

    /// Where the control row's centre sits, as a fraction of the screen's height from
    /// the top: close to the text it acts on (Alex, Beta 45 feedback, 25 Nov 2026).
    private static let controlsCentreFraction: CGFloat = 0.75

    /// From the mic's centre to the centre of the pictograms on either side of it.
    private static let sideControlDistance: CGFloat = 88
    /// Between the centres of copy and share, side by side right of the mic: their two
    /// 44 pt targets and 8 pt of air.
    private static let sideControlSpacing: CGFloat = 52

    /// Copy and share come and go in a short fade: only the character's drop moves.
    private static let sideControlTransition = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.15)),
        removal: .opacity.animation(.easeOut(duration: 0.15))
    )

    init(mode: RecordingMode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            OuisprMist()
                .opacity(contentOpacity)

            // The reader is only there for the bottom edge of the safe area, in the window
            // coordinates Home's mic was reported in.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    topRow
                        .padding(.horizontal, 20)
                        .padding(.top, Self.topRowHeight - 44)
                        .opacity(contentOpacity)

                    // The character, and the stage written under it.
                    //
                    // From Home it stays exactly where Home drew it, at the same size, for
                    // the whole dictation, and the stage takes the place of « Prêt à
                    // dicter » (Alex, 25 Nov 2026: in the first build it climbed to the top
                    // and shrank by 17 %, and the stage sat in the top bar). The slot runs
                    // from under the top row to where Home's heading starts; the character
                    // is drawn over it on Home's spot.
                    //
                    // Without a Home to line up on (onboarding, a launch that never drew
                    // Home), the screen keeps its own 200 pt slot.
                    if let home = homeSpot {
                        Color.clear
                            .frame(height: max(0, home.maxY + Self.homeHeadingGap(characterSide: home.height) - geo.frame(in: .global).minY - Self.topRowHeight))
                            .overlay { travellingSphere }
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 200)
                            .overlay { travellingSphere }
                            .padding(.top, 28)
                            .padding(.bottom, 16)
                    }

                    stageLabel
                        .frame(height: 34)
                        .opacity(stageLabelShown ? contentOpacity : 0)

                    // MARK: - Text zone (between the sphere and the controls)
                    // WHY flexible: it is the one zone allowed to give height back, so
                    // the sphere above and the controls below never move.
                    textZone
                        .frame(maxHeight: .infinity)
                        .opacity(contentOpacity)

                    // MARK: - Feedback line ("Copied!")
                    feedbackText
                        .frame(height: 30)
                        .padding(.top, 8)
                        .opacity(contentOpacity)

                    // MARK: - Controls (always in the same position)
                    controls(in: geo)
                        .frame(height: Self.micSlotHeight)
                        .padding(.top, 8)

                    // Puts the row's centre at three quarters of the screen. Every state
                    // of the row shares the slot, so all of them line up.
                    Spacer()
                        .frame(height: PrimaryMicAnchor.bottomSpacing(
                            containerHeight: geo.size.height,
                            slotHeight: Self.micSlotHeight,
                            centreFraction: Self.controlsCentreFraction
                        ))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .animation(.easeOut(duration: Motion.standard), value: showResult)
        .animation(.easeOut(duration: Motion.standard), value: showCopiedFeedback)
        .onChange(of: coordinator.status) { newStatus in
            // `handleStatusChange` is deliberately still driven by the real status: it
            // does not draw a stage, it reveals the result text and the error, and a
            // terminal status preempts the hold anyway (#309).
            handleStatusChange(newStatus)
            advanceDisplayedStatus(to: newStatus)
        }
        // The result can change after the status that revealed it (#467). On the
        // keyboard hand-off path `.ready` is published while `lastResult` still holds
        // the raw, on purpose — it is what the card should show if the keyboard never
        // reports back — and the polished text replaces it seconds later, with no
        // status change to carry it. A card snapshotted once at `.ready` therefore
        // kept the raw for as long as it was on screen.
        //
        // #467's actual fix is that a completed hand-off now returns the app to
        // `.idle`, which takes this screen down before the polished text arrives. This
        // is the belt: the card cannot go stale if the screen is up for any other
        // reason, and it costs one observer.
        //
        // A nil is deliberately not adopted. `startDictation` nils `lastResult` on
        // every entry path, and blanking a card the user is reading is not what that
        // write means — `startRecording` below clears the card itself when the reset
        // is this screen's own.
        .onChange(of: coordinator.lastResult) { _, newResult in
            guard showResult, let newResult, !newResult.isEmpty else { return }
            transcriptionResult = newResult
        }
        // A screen that appears mid-dictation adopts the stage in flight at once,
        // rather than starting from `.idle` and pretending to enter it.
        .onAppear {
            // A failure this screen was never mounted for gets read here (#320). A cold
            // start that dies puts `.failed` in place while `SwipeBackOverlayView` owns
            // the window; MainTabView inserts this view only once the overlay is gone, by
            // which time the status has stopped changing and `onChange` will never fire.
            // Only `.failed` is adopted on appear: `.ready` would replay the result card
            // and, in onboarding, its auto-advance.
            if coordinator.status == .failed {
                handleStatusChange(.failed)
            }
            advanceDisplayedStatus(to: coordinator.status)
            pinnedHomeFrame = homeSphere.homeFrame
            // The way in. The first frame is drawn with `appeared` false: the sphere on
            // Home's spot and the rest transparent, which is exactly what Home showed.
            withAnimation(reduceMotion ? .easeOut(duration: Motion.standard) : Self.enterAnimation) {
                appeared = true
            }
            // After Home's own words have faded (`HomeView.readySection`, Motion.quick).
            withAnimation(.easeOut(duration: Motion.quick).delay(mode == .standalone ? Motion.quick : 0)) {
                stageLabelShown = true
            }
        }
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
            // Reset, not merely cancel: `.onAppear` re-adopts the stage in flight, and
            // a decision left pending here would be re-affirmed as "already decided"
            // with no timer left to draw it. A fresh hold draws whatever it is handed.
            //
            // The drawn stage is reset with it, and the two must move together. A fresh
            // hold believes `.idle` is on screen; if the coordinator has also returned
            // to `.idle` by the time the screen comes back, `apply` answers `.unchanged`
            // and nothing reassigns `displayedStatus` -- leaving the travelling peak and
            // "Traitement..." drawn over an idle screen. Resetting only one of the two
            // is what makes them disagree.
            hold = TranscribingStageHold()
            displayedStatus = .idle
            stageLabelShown = false
        }
        .onChange(of: homeSphere.homeFrame) { _, frame in
            // Adopted only if Home had not reported its spot yet when this screen came up.
            if pinnedHomeFrame == nil { pinnedHomeFrame = frame }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Top Row

    /// The room the top bar used to take, kept so nothing below moves. The ✕ is in the
    /// control row now, beside the mic, at every stage (validated design, audit of
    /// 26 Nov 2026); the stage words are under the character.
    private var topRow: some View {
        Color.clear.frame(height: 44)
    }

    /// Whether the pipeline is recording or working on the audio, as drawn.
    private var isDictationInFlight: Bool {
        displayedStatus == .recording || isPostRecordingStage
    }

    /// Whether the pipeline is past the microphone and working on the audio or the
    /// transcript. Drives the sphere and the control row, both of which are the same
    /// for either stage.
    private var isPostRecordingStage: Bool {
        displayedStatus == .transcribing || displayedStatus == .processing
    }

    // MARK: - Stage Label

    /// A coloured dot and one or two words: what the phone is doing right now.
    ///
    /// Driven by `displayedStatus` rather than the coordinator's, so the label and the
    /// sphere change together (#309). The two post-recording stages keep their own
    /// words: naming the wrong stage is the complaint #267 exists to fix.
    private var stageLabel: some View {
        // The old words leave before the new ones come: a crossfade laid "Écoute 0:04"
        // and "Transcription en cours..." over each other for a moment, two lines of
        // different widths in one place (audit, 22 Nov 2026).
        ZStack {
            stageLabelContent
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: Motion.quick).delay(Motion.quick)),
                    removal: .opacity.animation(.easeOut(duration: Motion.quick))
                ))
        }
    }

    @ViewBuilder
    private var stageLabelContent: some View {
        if displayedStatus == .recording {
            stageLabelRow(text: "Listening", showsElapsedTime: true)
        } else if displayedStatus == .transcribing {
            stageLabelRow(text: "Transcribing...")
        } else if displayedStatus == .processing {
            stageLabelRow(text: "Cleaning up")
        } else if showResult {
            stageLabelRow(text: "Finished")
                .opacity(finishedShown && !finishedFaded ? 1 : 0)
                // Keyed on the text: a polished text that replaces the raw one is a new
                // reveal (#467), and « Terminé » waits for that one too.
                .task(id: transcriptionResult) {
                    finishedShown = false
                    finishedFaded = false
                    try? await Task.sleep(for: .seconds(revealDuration))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: Motion.quick)) { finishedShown = true }
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.6)) { finishedFaded = true }
                }
        }
    }

    /// How long the result's text takes to come into focus: the word-by-word reveal, or
    /// its single fade under Reduce Motion or for a long text (`RevealingText`).
    private var revealDuration: Double {
        let plan = WordRevealPlan(text: transcriptionResult ?? "")
        return plan.animatesWordByWord && !reduceMotion ? plan.totalDuration : Motion.standard
    }

    /// The stage, murmured: 13 pt in half ink, no dot and no colour. The character above
    /// already shows the stage; the words only confirm it (Alex's « Murmure », bench of
    /// 25 Nov 2026; Apple HIG, Feedback: unobtrusive but easy to check).
    private func stageLabelRow(text: LocalizedStringKey, showsElapsedTime: Bool = false) -> some View {
        // Quieter than before (Alex, 26 Nov 2026: « les secondes sont trop présentes »):
        // 12 pt, the word at 45 % ink (about 3:1, still legible), the seconds at 32 %,
        // a detail one finds when looking for it.
        HStack(spacing: 8) {
            Text(text)
                .foregroundStyle(Color.ouisprInk.opacity(0.45))
            if showsElapsedTime {
                ElapsedTimeText(levels: coordinator.levels)
                    .foregroundStyle(Color.ouisprInk.opacity(0.32))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sphere

    /// Whether the sphere flies between Home's spot and its own. Only from Home, and
    /// only once Home has drawn its sphere; Reduce Motion fades instead (HIG, Motion).
    private var sphereFlies: Bool {
        mode == .standalone && !reduceMotion && homeSphere.homeFrame != nil
    }

    /// Whether the sphere has to sit on Home's spot: always when there is one, since the
    /// character no longer moves for a dictation; otherwise the first frame and the way
    /// out.
    private var sphereAtHome: Bool {
        homeSpot != nil || (sphereFlies && (!appeared || isDismissing))
    }

    /// Home's character frame, in window coordinates, when this screen lines up on it.
    private var homeSpot: CGRect? {
        guard mode == .standalone, let home = pinnedHomeFrame ?? homeSphere.homeFrame, home.width > 0, home.height > 0 else { return nil }
        return home
    }

    /// Everything but the sphere: transparent on the first frame and on the way out,
    /// so Home shows through while the sphere travels. Onboarding has no Home under it
    /// and keeps the screen it always had.
    private var contentOpacity: Double {
        guard mode == .standalone else { return 1 }
        return appeared && !contentLeaving ? 1 : 0
    }

    /// The sphere stays opaque while it flies: it is the one thing that does not fade.
    /// Without a flight it fades with the rest.
    private var sphereOpacity: Double {
        sphereFlies ? 1 : contentOpacity
    }

    private var travellingSphere: some View {
        GeometryReader { slot in
            let frame = SphereFlight.frame(
                home: contentLeaving ? homeSphere.homeFrame : (pinnedHomeFrame ?? homeSphere.homeFrame),
                slot: slot.frame(in: .global),
                atHome: sphereAtHome
            )
            LevelDrivenSphere(
                levels: coordinator.levels,
                mood: sphereMood,
                listening: displayedStatus == .recording,
                sharesMotion: mode == .standalone
            )
                // Over a result: the drop and the laughing eyes, held a moment, then the
                // resting face. Under Reduce Motion the driver shows each held shape
                // without the passages between them.
                .task(id: showResult) {
                    resultRested = false
                    guard showResult else { return }
                    try? await Task.sleep(for: .seconds(InkGeometry.dropDuration + Self.laughingHold))
                    guard !Task.isCancelled else { return }
                    resultRested = true
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .opacity(sphereOpacity)
        }
    }

    private var sphereMood: ParticleSphereMood {
        switch displayedStatus {
        case .recording:
            return .listening
        case .transcribing, .processing:
            return .working
        case .idle, .requested, .ready, .failed:
            // The wave ends here, over its result: drop, laughing eyes, rest.
            guard showResult else { return .resting }
            return resultRested ? .resting : .done
        }
    }

    /// How long the laughing eyes stay before the resting face comes back.
    static let laughingHold = 1.2

    // MARK: - Text Zone

    @ViewBuilder
    private var textZone: some View {
        if showResult, let result = transcriptionResult {
            // WHY GeometryReader + ScrollView combo:
            // GeometryReader gives us the available height so we can
            // vertically center short text. ScrollView handles long text
            // that exceeds the zone. Short text sits centered; long text scrolls.
            GeometryReader { zone in
                ScrollView {
                    RevealingText(result)
                        // A new text is a new reveal: the polished text can replace
                        // the raw one while this screen is up (#467).
                        .id(result)
                        .foregroundStyle(Color.ouisprTextPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(minHeight: zone.size.height)
                }
                // A long text scrolls under a soft top edge instead of being cut by
                // the sphere's zone (bench 3).
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .transition(.opacity)
        } else if showError, let error = errorMessage {
            // Neutral, not alarming: a failed dictation is not a danger, and red is the
            // colour this screen keeps for "recording" (audit, 22 Nov 2026). The reason,
            // then the way forward.
            // One style, the screen's own: the reason in body text, the way forward as
            // a word in ink. No icon, no tinted pill (Alex, 25 Nov 2026).
            VStack(spacing: 10) {
                Text(error)
                    .font(.ouisprBody)
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: retryAfterError) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Retry")
                            .font(.ouisprBody.weight(.semibold))
                    }
                    .foregroundStyle(Color.ouisprInk)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressStyle())
            }
            .transition(stageTransition)
        } else {
            // Nothing to read yet. The zone keeps its height.
            Color.clear
        }
        // Onboarding: auto-advance handled in handleStatusChange
    }

    // MARK: - Feedback Line

    @ViewBuilder
    private var feedbackText: some View {
        if showCopiedFeedback {
            // A label one reads from arm's length, with the haptic of the tap (audit of
            // 26 Nov 2026, n°15: the caption-sized « Copié ! » went unseen).
            Label("Copied!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ouisprSuccess)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(Color.ouisprSuccess.opacity(0.12)))
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            // Empty placeholder to maintain layout
            Text(" ")
                .font(.ouisprCaption)
        }
    }

    // MARK: - Controls

    /// The mic in the middle, a bare pictogram on either side: cancel on its left while
    /// a dictation runs, copy on its left and share on its right with a result.
    ///
    /// The mic is the one filled shape; the pictograms are ink at half strength, with no
    /// disc or circle, so nothing competes with it (Alex, Beta 45 feedback, 25 Nov 2026:
    /// the black ✕ disc read as the main button). They fade in and out: the only drop
    /// left on this screen is the character's, at the end of a dictation.
    ///
    /// From Home the mic starts on Home's own mic and travels up to this row, as the
    /// character does, so the button the user tapped never jumps (#788).
    private func controls(in geo: GeometryProxy) -> some View {
        let result = shareableResult
        return ZStack {
            Group {
                // One ✕, always in the same place, named for what it does at the time.
                // The onboarding has no way out of this screen but its own pages.
                if mode == .standalone {
                    sideControl(
                        symbol: "xmark",
                        label: isDictationInFlight ? "Cancel" : "Close",
                        action: cancelOrClose
                    )
                    .offset(x: -Self.sideControlDistance)
                }
                if let result {
                    sideControl(symbol: "doc.on.doc", label: "Copy") { copyToPasteboard(result) }
                        .offset(x: Self.sideControlDistance)
                        .transition(Self.sideControlTransition)
                    ShareLink(item: result) {
                        sideControlGlyph("square.and.arrow.up")
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Share")
                    .offset(x: Self.sideControlDistance + Self.sideControlSpacing)
                    .transition(Self.sideControlTransition)
                }
            }
            .opacity(contentOpacity)

            mic
                .offset(y: micFlightOffset(in: geo))
                .opacity(micFlies ? 1 : contentOpacity)
        }
        .frame(maxWidth: .infinity)
    }

    /// Whether the mic travels between Home's mic and this row. Reduce Motion fades.
    private var micFlies: Bool {
        mode == .standalone && !reduceMotion && micAnchor.centerY != nil
    }

    /// How far below its row the mic is drawn: on Home's mic on the first frame and on
    /// the way out, on its row otherwise. Its row's centre is known from the layout
    /// itself (`controlsCentreFraction`), so the first frame already has it.
    private func micFlightOffset(in geo: GeometryProxy) -> CGFloat {
        guard micFlies, !appeared || isDismissing else { return 0 }
        let rowCentre = geo.frame(in: .global).minY + geo.size.height * Self.controlsCentreFraction
        return PrimaryMicAnchor.flightOffset(anchorY: micAnchor.centerY, slotCentreY: rowCentre)
    }

    /// One mic for every stage: its disc stays, the stop square appears inside it.
    private var mic: some View {
        let recording = displayedStatus == .recording && !isDismissing
        let working = isPostRecordingStage && !isDismissing
        let phase: InkMicButton.Phase = recording ? .listening : working ? .working : .resting
        return InkMicButton(phase: phase) {
            if recording { stopRecording() } else if !working { startRecording() }
        }
        .accessibilityLabel(recording ? Text("Stop recording") : Text("New dictation"))
        .accessibilityHidden(working)
    }

    /// A bare pictogram in half-strength ink, on a 44 pt target (Apple HIG, minimum
    /// hit target).
    private func sideControl(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sideControlGlyph(symbol)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
    }

    private func sideControlGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.ouisprInk.opacity(0.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    /// How a stage's content comes and goes: a fade with a slight scale, or a fade
    /// alone under Reduce Motion.
    private var stageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    /// The text the copy and share buttons act on: a result on screen, outside
    /// onboarding, where the screen moves on by itself a moment later.
    private var shareableResult: String? {
        guard mode == .standalone, showResult else { return nil }
        return transcriptionResult
    }

    // MARK: - Actions

    /// Leave: cancel a dictation in flight, or close the screen on a result.
    private func cancelOrClose() {
        HapticFeedback.recordingStopped()
        guard mode == .standalone else {
            // Onboarding keeps this screen up: only the dictation goes.
            coordinator.resetStatus()
            return
        }
        // Step 1: everything but the sphere fades out, the error and the result with it,
        // while the sphere flies back to Home's spot.
        // Step 2: when it lands, reset the status. That takes this screen down and shows
        // Home's sphere in the same frame, on the same spot, drawing the same simulation:
        // the hand-over has nothing to see.
        // Generation guard (issue #60): if a new dictation started while the
        // dismiss animation ran, this stale reset must not tear it down.
        let generation = coordinator.dictationGeneration
        withAnimation(Self.contentExitAnimation) {
            contentLeaving = true
        }
        withAnimation(reduceMotion ? .easeOut(duration: Motion.standard) : Self.exitAnimation) {
            isDismissing = true
        } completion: {
            guard coordinator.dictationGeneration == generation else { return }
            coordinator.resetStatus()
        }
    }

    private func copyToPasteboard(_ result: String) {
        UIPasteboard.general.string = result
        showCopiedFeedback = true
        HapticFeedback.recordingStopped()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedFeedback = false
        }
    }

    /// Onboarding goes back to its practice prompt; elsewhere the dictation starts again.
    private func retryAfterError() {
        guard mode != .onboarding else {
            withAnimation(Self.stageAnimation) {
                errorMessage = nil
                showError = false
                showResult = false
            }
            return
        }
        startRecording()
    }

    private func startRecording() {
        // Asked BEFORE the result state is cleared (#484): a tap that ends on the preparation
        // screen has not started a dictation, and wiping the transcription the user is looking
        // at on the way there would throw away a result for a recording that never happened.
        guard case .startDictation = coordinator.recordTapDecision else {
            presentModelPreparation()
            return
        }

        // Reset previous result state
        transcriptionResult = nil
        showResult = false
        showError = false
        errorMessage = nil
        showCopiedFeedback = false

        HapticFeedback.recordingStarted()
        coordinator.startDictation(origin: .app)
    }

    private func stopRecording() {
        HapticFeedback.recordingStopped()
        coordinator.stopDictation(cause: .appButton)
    }

    // MARK: - Stage display (#309)

    /// Move `displayedStatus` toward `status`, honouring the transcription floor.
    ///
    /// The decision is `TranscribingStageHold`'s, in OuisprCore, where it is tested.
    /// What lives here is only this screen's timer — a `Task` rather than a `Timer`,
    /// because it has to be cancelled from the view and cancellation is what keeps a
    /// terminal status from ever waiting behind a stage that no longer matters.
    private func advanceDisplayedStatus(to status: DictationStatus) {
        switch hold.apply(status, now: Date()) {
        case .unchanged:
            break
        case .draw(let drawn):
            holdTask?.cancel()
            holdTask = nil
            withAnimation(Self.stageAnimation) {
                displayedStatus = drawn
            }
        case .hold(_, let interval):
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                if case .draw(let drawn) = hold.release(now: Date()) {
                    withAnimation(Self.stageAnimation) {
                        displayedStatus = drawn
                    }
                }
            }
        }
    }

    // MARK: - Status Handling

    private func handleStatusChange(_ newStatus: DictationStatus) {
        switch newStatus {
        case .ready:
            if let result = coordinator.lastResult, !result.isEmpty {
                transcriptionResult = result
                withAnimation(.easeOut(duration: Motion.emphasized)) {
                    showResult = true
                }
                // Auto-advance to success screen in onboarding mode
                // Shows transcription result for 1.5s then triggers onComplete
                if mode == .onboarding {
                    // Generation guard (issue #60): if the user started a new dictation
                    // during the 1.5s delay, this stale auto-advance must not fire.
                    let generation = coordinator.dictationGeneration
                    Task {
                        try? await Task.sleep(for: .milliseconds(1500))
                        await MainActor.run {
                            guard coordinator.dictationGeneration == generation else { return }
                            coordinator.resetStatus()
                            onComplete?()
                        }
                    }
                }
            }
        case .failed:
            // The reason the app itself recorded, not the transcription property (#320).
            // `lastResult` only ever holds transcribed text and `startDictation` nils it
            // on every entry path, so reading it here was reading nil one hundred percent
            // of the time and printing the fallback -- which named the model download,
            // whatever had actually failed.
            //
            // The fallback now names nothing. A failure with no recorded reason is a
            // failure we cannot explain, and the honest sentence for that is the one that
            // explains nothing. Every cause we *can* name already writes its own message
            // at its own call site.
            let message = DictationErrorChannel.current ?? String(localized: "The dictation could not finish. Try again in a moment.")
            // Both in one animated change: the error is drawn only once it has a message,
            // so a message set outside the animation would make it pop in a frame.
            withAnimation(Self.stageAnimation) {
                errorMessage = message
                showError = true
            }
        default:
            break
        }
    }
}

#Preview("Recording - Idle") {
    RecordingView(mode: .standalone)
        .environmentObject(DictationCoordinator.shared)
}

/// The sphere, reading the microphone level itself.
///
/// WHY a view of its own: the level changes about twelve times a second. Observed here,
/// only this view re-renders; read in `RecordingView`'s body, the whole screen did
/// (audit, 22 Nov 2026, finding 7).
private struct LevelDrivenSphere: View {
    @ObservedObject var levels: DictationLevels
    let mood: ParticleSphereMood
    let listening: Bool
    let sharesMotion: Bool

    var body: some View {
        InkCharacterView(
            mood: mood,
            voiceLevel: listening ? levels.recentPeak : 0,
            sharesMotion: sharesMotion
        )
    }
}

/// The elapsed time next to "Listening", reading it itself for the same reason.
private struct ElapsedTimeText: View {
    @ObservedObject var levels: DictationLevels
    /// The last time shown while it ran. The count is reset to zero as the recording
    /// stops, while this label is still fading out, and it read "0:00" for a moment.
    @State private var held = "0:00"

    var body: some View {
        Text(verbatim: levels.seconds > 0 ? levels.elapsedLabel : held)
            .monospacedDigit()
            .onChange(of: levels.elapsedLabel) { _, label in
                if levels.seconds > 0 { held = label }
            }
    }
}
