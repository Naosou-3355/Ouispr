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
/// - Recording: "Listening", the sphere follows the voice, cancel / mic / validate
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

    /// Where Home's mic is on screen, which the button below lines up on (#788).
    @ObservedObject private var micAnchor = PrimaryMicAnchor.shared

    /// Height of the slot the mic / stop button is centred in.
    private static let micSlotHeight: CGFloat = 100

    /// Space under that slot when there is no Home mic to line up on: onboarding, or a
    /// launch that never drew Home. The layout this screen always had.
    private static let defaultBottomSpacing: CGFloat = 40

    init(mode: RecordingMode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.ouisprBackground.ignoresSafeArea()

            // The reader is only there for the bottom edge of the safe area, in the window
            // coordinates Home's mic was reported in.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    topRow
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // The same sphere as on Home, a little smaller to leave the text
                    // its room. It never leaves: only its mood changes.
                    ParticleSphereView(mood: sphereMood, voiceLevel: voiceLevel)
                        .frame(maxWidth: 200, maxHeight: 200)
                        .padding(.top, 28)
                        .padding(.bottom, 16)

                    // MARK: - Text zone (between the sphere and the controls)
                    // WHY flexible: it is the one zone allowed to give height back, so
                    // the sphere above and the controls below never move.
                    textZone
                        .frame(maxHeight: .infinity)

                    // MARK: - Feedback line ("Copied!")
                    feedbackText
                        .frame(height: 30)
                        .padding(.top, 8)

                    // MARK: - Controls (always in the same position)
                    controls
                        .frame(height: Self.micSlotHeight)
                        .padding(.top, 16)

                    // Whatever lifts the mic's centre to the height of Home's mic, so the
                    // one the user just tapped does not jump down when this screen covers it
                    // (#788). Every state of the row shares the slot, so all of them line up.
                    Spacer()
                        .frame(height: bottomSpacing(in: geo))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .opacity(isDismissing ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: showResult)
        .animation(.easeOut(duration: 0.3), value: showCopiedFeedback)
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
        }
        .navigationBarHidden(true)
    }

    // MARK: - Button Height

    /// Space under the button slot. Home's mic is only an anchor for the standalone screen,
    /// the one Home opens; onboarding keeps its own layout.
    private func bottomSpacing(in geo: GeometryProxy) -> CGFloat {
        PrimaryMicAnchor.bottomSpacing(
            anchorY: mode == .standalone ? micAnchor.centerY : nil,
            containerMaxY: geo.frame(in: .global).maxY,
            slotHeight: Self.micSlotHeight,
            fallback: Self.defaultBottomSpacing
        )
    }

    // MARK: - Top Row

    /// The close button on the left (standalone only) and the stage label, centred.
    private var topRow: some View {
        ZStack {
            HStack {
                if mode == .standalone {
                    Button(action: cancelOrClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ouisprTextPrimary)
                            .frame(width: 44, height: 44)
                            .ouisprGlass(in: Circle())
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Close")
                    // While a dictation is in flight the control row carries the way
                    // out, labelled as what it is: a cancel. Hidden rather than
                    // removed, so nothing in this row moves.
                    .opacity(isDictationInFlight ? 0 : 1)
                    .disabled(isDictationInFlight)
                    .accessibilityHidden(isDictationInFlight)
                }
                Spacer()
            }
            stageLabel
        }
        .frame(height: 44)
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
    @ViewBuilder
    private var stageLabel: some View {
        if displayedStatus == .recording {
            stageLabelRow(dot: .ouisprRecording, text: "Listening", detail: formattedTime)
        } else if displayedStatus == .transcribing {
            stageLabelRow(dot: .ouisprAccent, text: "Transcribing...", detail: nil)
        } else if displayedStatus == .processing {
            stageLabelRow(dot: .ouisprAccent, text: "Cleaning up", detail: nil)
        } else if showResult {
            stageLabelRow(dot: .ouisprSuccess, text: "Finished", detail: nil)
        }
    }

    private func stageLabelRow(dot: Color, text: LocalizedStringKey, detail: String?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(Color.ouisprTextSecondary)
            if let detail {
                Text(verbatim: detail)
                    .monospacedDigit()
                    .foregroundStyle(Color.ouisprTextTertiary)
            }
        }
        .font(.ouisprStageLabel)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sphere

    private var sphereMood: ParticleSphereMood {
        switch displayedStatus {
        case .recording:
            return .listening
        case .transcribing, .processing:
            return .working
        case .idle, .requested, .ready, .failed:
            return showResult ? .done : .resting
        }
    }

    /// The loudest of the most recent levels, 0 to 1.
    ///
    /// WHY the last few and not the last one: the coordinator publishes a waveform
    /// snapshot, a row of buckets whose newest end is on the right. One bucket is one
    /// short slice of sound; taking the peak of a few is what makes a syllable reach
    /// the sphere whole.
    private var voiceLevel: Double {
        guard displayedStatus == .recording else { return 0 }
        return Double(coordinator.bufferEnergy.suffix(4).max() ?? 0)
    }

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
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                Text(error)
                    .font(.ouisprCaption)
                    .foregroundColor(.ouisprRecording)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if mode == .onboarding {
                    Button("Retry") {
                        errorMessage = nil
                        showError = false
                        showResult = false
                    }
                    .font(.ouisprBody)
                    .foregroundColor(.ouisprAccent)
                    .padding(.top, 8)
                }
            }
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
            Text("Copied!")
                .font(.ouisprCaption)
                .foregroundStyle(Color.ouisprSuccess)
        } else {
            // Empty placeholder to maintain layout
            Text(" ")
                .font(.ouisprCaption)
        }
    }

    // MARK: - Controls

    /// The control row, which changes with the stage and never moves.
    /// WHY always present: Prevents layout jumps. The mic is the visual anchor
    /// of the screen, at the height of Home's own (#788).
    @ViewBuilder
    private var controls: some View {
        if displayedStatus == .recording {
            HStack(spacing: 28) {
                sideButton(symbol: "xmark", label: "Cancel", action: cancelOrClose)
                listeningMicButton
                sideButton(symbol: "checkmark", label: "Stop recording", action: stopRecording)
            }
        } else if isPostRecordingStage {
            // The cleaning stage can last several seconds: the way out stays in reach.
            Button(action: cancelOrClose) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Cancel")
                        .font(.ouisprBody)
                }
                .foregroundStyle(Color.ouisprTextPrimary)
                .padding(.horizontal, 22)
                .frame(minHeight: 52)
                .ouisprGlassBar()
            }
            .buttonStyle(GlassPressStyle())
        } else {
            // Idle / result state: mic button ready for (new) recording, with the
            // two things a result is for on either side of it.
            HStack(spacing: 28) {
                if let result = shareableResult {
                    sideButton(symbol: "doc.on.doc", label: "Copy") { copyToPasteboard(result) }
                } else {
                    sideButtonPlaceholder
                }
                AnimatedMicButton(status: .idle) {
                    startRecording()
                }
                .accessibilityLabel("New dictation")
                if let result = shareableResult {
                    ShareLink(item: result) {
                        sideButtonFace(symbol: "square.and.arrow.up")
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Share")
                } else {
                    sideButtonPlaceholder
                }
            }
        }
    }

    /// The text the copy and share buttons act on: a result on screen, outside
    /// onboarding, where the screen moves on by itself a moment later.
    private var shareableResult: String? {
        guard mode == .standalone, showResult else { return nil }
        return transcriptionResult
    }

    /// The mic while it listens: the sphere's gradient, and a tap ends the dictation,
    /// as the checkmark next to it does.
    private var listeningMicButton: some View {
        Button(action: stopRecording) {
            ZStack {
                OuisprHalo(isPill: false, color: .ouisprRecording, opacity: 0.5, lineWidth: 2)
                Circle()
                    .fill(OuisprSphereGradient.linear)
                    .frame(width: 72, height: 72)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel("Stop recording")
    }

    private func sideButton(symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sideButtonFace(symbol: symbol)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
    }

    private func sideButtonFace(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.ouisprTextPrimary)
            .frame(width: 52, height: 52)
            .ouisprGlass(in: Circle())
    }

    /// Takes a side button's room, so the mic stays centred when there is none.
    private var sideButtonPlaceholder: some View {
        Color.clear
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
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
        // Step 1: animate RecordingView out
        withAnimation(.easeOut(duration: 0.25)) {
            isDismissing = true
        }
        // Step 2: after animation, reset status (no animation leak to HomeView).
        // Generation guard (issue #60): if a new dictation started while the
        // dismiss animation ran, this stale reset must not tear it down.
        let generation = coordinator.dictationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
        coordinator.stopDictation()
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
            displayedStatus = drawn
        case .hold(_, let interval):
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                if case .draw(let drawn) = hold.release(now: Date()) {
                    displayedStatus = drawn
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
                withAnimation(.easeOut(duration: 0.4)) {
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
            showError = true
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
            errorMessage = DictationErrorChannel.current ?? String(localized: "The dictation failed.")
        default:
            break
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let totalSeconds = Int(coordinator.bufferSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Recording - Idle") {
    RecordingView(mode: .standalone)
        .environmentObject(DictationCoordinator.shared)
}
