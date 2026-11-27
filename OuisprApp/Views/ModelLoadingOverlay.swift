// OuisprApp/Views/ModelLoadingOverlay.swift
// Full-screen blocking screen shown while a model is downloading, compiling
// for the Neural Engine, or being loaded into RAM. Issues #144, #708.
import SwiftUI
import OuisprCore

/// Full-screen cover that surfaces long-running model preparation work to the user.
///
/// Why this exists:
/// Whisper turbo (~645 MB) takes about three and a half minutes of one-off Core ML
/// compilation on a 15 Pro Max, and a couple of seconds to load into RAM every time
/// after that. The "~2 min" figure this comment used to quote was never measured on
/// this variant at all — it described the ~954 MB one issue #408 replaced. Four cold
/// readings of the current variant now live in `ModelInfo.firstPreparationSeconds`,
/// which is where the number belongs. Without a blocking UI the user could mistake
/// the wait for a frozen app, tap the keyboard mic mid-load, and trigger a
/// `Swift.CancellationError` cascade (issue #144). The overlay refuses any further
/// model interaction until `modelLoadState == .ready`.
///
/// Refusing to let the user act made it this screen's job to SAY how long the wait is
/// (issue #432), and then how far along it is: a coarse countdown under the compile,
/// "About 3 minutes left", then "Less than a minute left", held (issue #533). The rules
/// live in `ModelPreparationCountdown`, where they are tested.
///
/// WHAT IT LOOKS LIKE, AND WHY (lot 1.1, Alex's bench of 27 Nov 2026, replacing #708's
/// ring and step card): the ink character the user will meet on Home, whose eyes fill with
/// ink as the preparation runs and come alive as laughing eyes when it is done; the
/// percentage right under them; a title and a subtitle; one status line; a friendly line at
/// each quarter; and a quiet notice at the foot. One centred block on the 8 pt grid
/// (`ModelPreparationMetrics`), every text slot holding the room of its longest wording, so
/// a phase change only swaps content and nothing moves. No button.
///
/// WHAT THE PERCENTAGE MEANS: the download's real fraction, then an estimate of the
/// compile and the load, which report no progress (`ModelPreparationProgress`). It never
/// reads 100 % before the model is really ready.
///
/// The overlay observes two signals to decide which phase to show:
/// 1. `ModelManager.modelStates[id]` — `.downloading`, `.prewarming`, `.ready`
/// 2. `ModelManager.modelLoadState` (mirrored from the App Group via Combine) —
///    `.loading` once `DictationCoordinator.preloadActiveModel` is in flight.
struct ModelLoadingOverlay: View {
    @ObservedObject var modelManager: ModelManager

    /// Identifier of the model the user just acted on (download or select).
    /// Drives the phase logic and which copy is shown.
    let modelIdentifier: String

    /// Two-way binding controlled by the parent. The overlay flips it to false
    /// once the model becomes ready so the cover dismisses itself.
    @Binding var isPresented: Bool

    /// The user-facing flow that caused preparation to be shown.
    let context: ModelPreparationContext

    @State private var showCompletion = false
    @State private var activeContext: ModelPreparationContext

    /// Set when the load ended because the app STOPPED WAITING for it, rather than
    /// because it finished (third review, finding D).
    ///
    /// Both outcomes leave `modelLoadState == .idle`, and `rawPhase` maps a downloaded
    /// model plus `.idle` to `.ready` — so a deadline expiring with this screen up, the
    /// keyboard-cold-start case issue #428 exists for, showed the user the "Model ready"
    /// checkmark while the compile was still running and no engine was loaded. The
    /// reason travels on the notification that already drives this screen.
    @State private var loadGaveUp = false

    /// Tracks whether we have ever observed an active prep phase (downloading,
    /// compiling, or loading). Without this, the overlay would auto-dismiss
    /// when presented synchronously by the parent before `downloadModel`
    /// has had a chance to flip `modelStates[id]` from `.notDownloaded` to
    /// `.downloading` — the onboarding race that surfaced after f5ba7ab.
    @State private var hasSeenWorkPhase = false

    /// Whether every file the model needs was on disk when the screen opened (#708).
    ///
    /// Decides the phase drawn before any work has been seen: the optimization frame for a
    /// model already downloaded, the download frame otherwise. Read once, in `init`, so the
    /// very first frame is already the right one; an `onAppear` would come one frame late,
    /// and one frame of a download that does not happen is the defect this fixes.
    @State private var filesOnDiskAtOpen: Bool

    /// The last work phase drawn, held while the model state already reads `.ready` but
    /// the completion has not been decided yet (`checkForCompletion` runs in `onChange`,
    /// after the frame that saw the change). Without it that frame would draw the ready
    /// copy over the work phase's eyes, or flash back to the opening phase.
    @State private var lastWorkPhase: ModelPreparationPhase

    /// When this screen first saw a COLD preparation of a model measured in minutes —
    /// the clock the countdown runs on (issue #533). Nil means no countdown at all.
    ///
    /// WHY NEVER RESET: a download-then-prepare goes `.compiling` → `.loading`, and to the
    /// user that is one wait. Restarting the clock at the hand-over would add minutes back.
    ///
    /// WHY THE WALL CLOCK: time spent in the background keeps counting. A compile throttled
    /// there (#472) only reaches the floor earlier and holds it longer, which is the
    /// designed behaviour. When the screen appears mid-preparation (keyboard cold start into
    /// a compile already running) the anchor is late and the countdown overstates what is
    /// left — the safe direction under #432's rule, so no persisted start time is added.
    @State private var preparationStartedAt: Date?

    /// When this screen first saw the compile or the load running: the clock the
    /// preparation's share of the percentage runs on (`ModelPreparationProgress`). Unlike
    /// `preparationStartedAt` it runs for every model, warm or cold, measured or not.
    @State private var preparationSeenAt: Date?

    /// The highest download fraction seen. A file restarted after a stall can report less
    /// than before, and the percentage never goes back.
    @State private var downloadHighWater = 0.0

    private typealias Phase = ModelPreparationPhase
    private typealias Metrics = ModelPreparationMetrics

    init(
        modelManager: ModelManager,
        modelIdentifier: String,
        context: ModelPreparationContext = .modelSelection,
        isPresented: Binding<Bool>
    ) {
        self.modelManager = modelManager
        self.modelIdentifier = modelIdentifier
        self.context = context
        self._isPresented = isPresented
        self._activeContext = State(initialValue: context)
        let filesOnDisk = ModelManager.hasCompleteFilesOnDisk(modelIdentifier)
        self._filesOnDiskAtOpen = State(initialValue: filesOnDisk)
        self._lastWorkPhase = State(initialValue: Phase.displayed(
            raw: .ready,
            hasSeenWorkPhase: false,
            filesOnDisk: filesOnDisk
        ))
    }

    var body: some View {
        ZStack {
            // The still background Home, the history and the recording screen share.
            OuisprBackdrop().ignoresSafeArea()

            VStack(spacing: 0) {
                // WHY THIS INSET (#708): in the onboarding the shell's progress bar row sits
                // above this screen, outside it. The in-app contexts have no bar, so their
                // content is pushed down by the bar row's height and the face lands at the
                // same y in both. The context the screen was raised with decides it, not
                // `activeContext`: a keyboard request arriving mid-way turns one in-app
                // context into another and must not move anything.
                if context != .onboarding {
                    Color.clear.frame(height: OnboardingMetrics.topRowHeight)
                }

                // Centred in the height left, the notice at the foot. With the largest text
                // sizes the whole can be taller than the screen: it scrolls then, notice
                // included, rather than being cut. One tree for both cases, so the face
                // keeps its state if the text size changes under it.
                GeometryReader { geo in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: Metrics.percentToTitle)
                            content
                            Spacer(minLength: Metrics.percentToTitle)
                            footer
                                .padding(.bottom, Metrics.footerBottom)
                        }
                        .frame(minHeight: geo.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(.horizontal)
        }
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: .ouisprModelLoadStateChanged)) { note in
            if let reason = note.userInfo?["reason"] as? String,
               ModelPreparationOutcome.reasonMeansGaveUp(reason) {
                loadGaveUp = true
            }
            checkForCompletion()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ouisprKeyboardPreparationRequested)) { _ in
            activeContext = .keyboardColdStart
        }
        .onChange(of: currentModelState) { _, _ in
            checkForCompletion()
        }
        .onAppear {
            checkForCompletion()
        }
        // `initial: true` also runs this for the phase the screen opens on, which is the
        // keyboard cold start's case: it can arrive with the load already in flight.
        .onChange(of: currentPhase, initial: true) { _, newPhase in
            if newPhase != .ready {
                lastWorkPhase = newPhase
            }
            startClocksIfWorking()
        }
        // The phase on screen does not change when a model already on disk starts its
        // compile: it was drawn as compiling from the first frame. The model's own state
        // does, so the clocks also listen to it (review of lot 1.1, finding 1).
        .onChange(of: rawPhase) { _, _ in
            startClocksIfWorking()
        }
        .onChange(of: downloadFraction) { _, fraction in
            downloadHighWater = max(downloadHighWater, fraction ?? 0)
        }
    }

    // MARK: - Layout

    /// The one block (lot 1.1): the face, its figure, the title, the subtitle, the status
    /// and its friendly line, on the 8 pt grid (`ModelPreparationMetrics`).
    ///
    /// WHY EVERY TEXT HOLDS THE ROOM OF ITS LONGEST WORDING: the block is centred, so a
    /// line that grew or shrank between phases would move everything above and below it.
    /// Each slot lays out all its wordings and shows one, so a phase change only swaps
    /// what is in it, at every text size.
    ///
    /// WHY A TIMELINE: the preparation's share of the figure moves with time
    /// (`ModelPreparationProgress`), and so does the countdown in the status line. Twice a
    /// second is enough for a whole percent and a minute boundary.
    private var content: some View {
        let phase = displayedPhase
        return TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let fraction = progress(of: phase, at: timeline.date)
            let percent = ModelPreparationProgress.percent(fraction)
            VStack(spacing: 0) {
                ModelPreparationFace(fraction: fraction, isReady: phase == .ready)

                percentLabel(percent)
                    .padding(.top, Metrics.faceToPercent)

                ZStack {
                    title(for: .downloading).hidden()
                    title(for: .ready).hidden()
                    title(for: phase)
                        .accessibilityAddTraits(.isHeader)
                }
                .font(.title.bold())
                .foregroundStyle(Color.ouisprTextPrimary)
                .padding(.top, Metrics.percentToTitle)

                ZStack {
                    subtitle(for: .downloading).hidden()
                    subtitle(for: .ready).hidden()
                    subtitle(for: phase)
                }
                .font(.body)
                .foregroundStyle(Color.ouisprTextSecondary)
                .padding(.top, Metrics.titleToSubtitle)

                ZStack {
                    // The longest wordings, with wide figures, hold the room.
                    Text("Downloading · \(888) of \(888) MB").hidden()
                    Text("Loading the model · about \(88) min left").hidden()
                    Text("Loading the model · under a minute left").hidden()
                    statusLine(for: phase, at: timeline.date)
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.ouisprTextSecondary)
                .padding(.top, Metrics.subtitleToStatus)

                milestoneLine(ModelPreparationMilestone.reached(percent: percent, isReady: phase == .ready))
                    .font(.subheadline)
                    .foregroundStyle(Color.ouisprTextTertiary)
                    .padding(.top, Metrics.statusToMessage)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: Metrics.maxTextWidth)
            .frame(maxWidth: .infinity)
        }
        // A phase change swaps what is in each slot: the fade is the only movement.
        .animation(.easeInOut(duration: Motion.standard), value: phase)
    }

    /// « 42 % », formatted for the locale (a narrow space before the sign in French), in
    /// tabular figures so the number keeps its width as it counts.
    private func percentLabel(_ percent: Int) -> some View {
        Text(Double(percent) / 100, format: .percent.precision(.fractionLength(0)))
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color.ouisprInk.opacity(0.7))
            .contentTransition(.identity)
            .accessibilityLabel(Text("Progress", comment: "VoiceOver name of the model preparation percentage (lot 1.1)."))
            .accessibilityValue(Text(Double(percent) / 100, format: .percent.precision(.fractionLength(0))))
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// The preparation's progress, 0 to 1, by `ModelPreparationProgress`'s rules.
    private func progress(of phase: Phase, at date: Date) -> Double {
        ModelPreparationProgress.fraction(
            phase: phase,
            downloadFraction: max(downloadHighWater, downloadFraction ?? 0),
            includesDownload: !filesOnDiskAtOpen,
            preparationElapsed: preparationSeenAt.map { date.timeIntervalSince($0) },
            measuredSeconds: ModelInfo.forIdentifier(modelIdentifier)?.firstPreparationSeconds
        )
    }

    // MARK: - Title and subtitle

    private func title(for phase: Phase) -> Text {
        phase == .ready
            ? Text("Your model is ready", comment: "Model preparation screen title, once the model is ready (#708).")
            : Text("Preparing your model", comment: "Model preparation screen title, while downloading, optimizing or loading (#708).")
    }

    /// The subtitle names the model, and in the onboarding the language it was picked for
    /// (#649 decision 4: the screen says the model is the best one for the user's language
    /// and iPhone).
    private func subtitle(for phase: Phase) -> Text {
        if phase == .ready {
            return Text(
                "\(modelName) runs on your iPhone. Dictation works even without a network.",
                comment: "Model preparation screen subtitle, once ready. The placeholder is the model's name (Parakeet v3) (#708)."
            )
        }
        guard context == .onboarding else {
            return Text(
                "\(modelName). Once ready, everything runs offline.",
                comment: "Model preparation screen subtitle in the app (model switch, keyboard cold start). The placeholder is the model's name (#708)."
            )
        }
        if let language = spokenLanguagePhrase {
            return Text(
                "\(modelName), picked for \(language) and this iPhone. After that, everything runs offline.",
                comment: "Onboarding model preparation subtitle (#708). First placeholder: the model's name (Parakeet v3). Second: the spoken language with its article in French (le français, l'anglais)."
            )
        }
        return Text(
            "\(modelName), picked for your language and this iPhone. After that, everything runs offline.",
            comment: "Onboarding model preparation subtitle when the language cannot be named in the sentence (#708). The placeholder is the model's name."
        )
    }

    private var modelName: String {
        ModelInfo.forIdentifier(modelIdentifier)?.localizedDisplayName ?? String(localized: "Voice model")
    }

    /// The language the onboarding picked this model for, ready to slot into the sentence,
    /// or nil for the sentence that does not name it. The rules are
    /// `ModelPreparationLanguagePhrase`'s.
    ///
    /// WHY `SpokenLanguage.forRecommendation()`: it is the input
    /// `ModelInfo.recommendedIdentifier()` chose this model from, so the sentence names the
    /// language that actually decided it. Named in the interface's language, which is the
    /// app's localization and not the device locale: a German iPhone reads the app in
    /// English, and "picked for Französisch" would be wrong twice.
    private var spokenLanguagePhrase: String? {
        let interfaceLanguage = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale(identifier: interfaceLanguage)
            .localizedString(forLanguageCode: SpokenLanguage.forRecommendation())
        return ModelPreparationLanguagePhrase.phrase(languageName: name, interfaceLanguage: interfaceLanguage)
    }

    private var downloadFraction: Double? {
        modelManager.downloadProgress[modelIdentifier].map(Double.init)
    }

    // MARK: - Status and friendly line

    /// One line saying what is happening (lot 1.1, « Une seule ligne »): the megabytes
    /// while downloading, the load with the #533 countdown when there is one, then
    /// nothing. The compile and the load read as one step: to the user both are the
    /// model getting ready on the phone.
    private func statusLine(for phase: Phase, at date: Date) -> Text {
        switch phase {
        case .downloading:
            guard let bytes = modelManager.downloadByteInfo[modelIdentifier] else {
                return Text("Downloading…", comment: "Model preparation status, before the first downloaded byte (lot 1.1).")
            }
            return Text(
                "Downloading · \(bytes.downloadedMB) of \(bytes.totalMB) MB",
                comment: "Model preparation status while downloading: megabytes done, then the total (lot 1.1)."
            )
        case .compiling, .loading:
            guard let preparationStartedAt, !loadGaveUp,
                  let countdown = ModelPreparationCountdown.at(
                    elapsedSeconds: Int(date.timeIntervalSince(preparationStartedAt)),
                    measuredSeconds: ModelInfo.forIdentifier(modelIdentifier)?.firstPreparationSeconds
                  ) else {
                return Text("Loading the model…", comment: "Model preparation status after the download (lot 1.1).")
            }
            switch countdown {
            case .minutesLeft(let minutes):
                return Text(
                    "Loading the model · about \(minutes) min left",
                    comment: "Model preparation status with the countdown of a long first preparation (lot 1.1, #533)."
                )
            case .underAMinute:
                return Text(
                    "Loading the model · under a minute left",
                    comment: "Model preparation status, last minute of a long first preparation (lot 1.1, #533)."
                )
            }
        case .ready:
            // Empty once ready (Alex, 27 Nov 2026): the title and the friendly line say it
            // already. The slot keeps its room, so nothing moves, and the words fade out.
            return Text(verbatim: "")
        }
    }

    /// The friendly line, one per quarter (Alex, 27 Nov 2026). It fades in at its
    /// milestone and stays until the next one; under 25 % its room stays empty.
    private func milestoneLine(_ milestone: ModelPreparationMilestone?) -> some View {
        ZStack {
            ForEach(ModelPreparationMilestone.allCases, id: \.self) { candidate in
                milestoneText(candidate).hidden()
            }
            if let milestone {
                milestoneText(milestone)
                    .id(milestone)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: milestone)
    }

    private func milestoneText(_ milestone: ModelPreparationMilestone) -> Text {
        switch milestone {
        case .quarter:
            return Text("The parakeet is warming up its voice.", comment: "Friendly line on the model preparation screen at 25 % (lot 1.1).")
        case .half:
            return Text("Halfway there. The coffee is still hot.", comment: "Friendly line on the model preparation screen at 50 % (lot 1.1).")
        case .threeQuarters:
            return Text("Just a few more words to learn.", comment: "Friendly line on the model preparation screen at 75 % (lot 1.1).")
        case .done:
            return Text("Ready to listen to you.", comment: "Friendly line on the model preparation screen once the model is ready (lot 1.1).")
        }
    }

    // MARK: - Footer

    /// The foot of the screen: the line about leaving it while the work runs, then, once
    /// ready, what to do next when there is something to do. Tertiary and not the accent:
    /// it is a notice, not a link (lot 1.1). Both wordings hold the slot, so the block
    /// above never moves.
    private var footer: some View {
        let phase = displayedPhase
        return ZStack {
            // Every wording this footer can show holds the room, whatever the context
            // becomes on the way (a keyboard request turns one in-app context into another).
            Group {
                Text("The download continues if you leave the app.")
                Text("Please wait for preparation to finish.")
                Text("Please stay on this page and do not leave the app.")
                Text("Return to your app and tap the microphone again.")
                Text("Tap again to start your dictation.")
            }
            .hidden()
            if phase == .ready {
                if let completionInstruction {
                    Text(completionInstruction)
                }
            } else {
                leaveNotice(isDownloading: phase == .downloading)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.ouisprTextTertiary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: Metrics.maxTextWidth)
        .animation(.easeInOut(duration: Motion.standard), value: phase)
    }

    /// What the user does next, once the model is ready.
    ///
    /// Only the two prepare-only contexts have anything to say here: they are the ones reached
    /// from a tap that deliberately does NOT become a recording, so the screen owes the user
    /// the action that does. Which sentence is a question about where they came from, not
    /// about the prepare-only rule — hence `startedFromAnotherApp` and not `isPrepareOnly`
    /// (#484). Onboarding and model selection dismiss into the screen the user was already on.
    ///
    /// WHY IT SURVIVED #708 AND LOT 1.1: neither brief draws it, both drawn for the
    /// onboarding, which has no instruction to give. For a user who tapped the keyboard's mic
    /// and was sent here, the instruction is the only thing on the ready screen that says the
    /// tap did not start a dictation, so it takes the footer's place there.
    private var completionInstruction: LocalizedStringKey? {
        switch activeContext {
        case .onboarding, .modelSelection:
            return nil
        case .keyboardColdStart:
            return "Return to your app and tap the microphone again."
        case .appRecordTap:
            return "Tap again to start your dictation."
        }
    }

    /// The line about leaving this screen. Which one is `ModelPreparationContext.leaveNotice`.
    ///
    /// WHICH OF THE FIRST TWO, and why it is not `isPrepareOnly` (#484): "stay on this
    /// page" is only sayable to someone who is on it. The keyboard cold start brings a user
    /// whose next move is to leave, so it asks for patience instead. The in-app tap does
    /// not — and staying in the foreground is what keeps the compile off the system's
    /// background throttle (#472), so it is the stronger of the two sentences and the right
    /// one there.
    ///
    /// THE THIRD is the onboarding variant (#675, #649 decision 6): while the onboarding's
    /// download runs, it survives leaving the app, so the screen says that instead.
    ///
    /// WHY NOT IN THE ACCENT ANY MORE (lot 1.1): #708 drew it in the accent as the
    /// caption's call to the user. Blue text reads as a link on iOS, and this one does
    /// nothing when tapped, so it is a quiet notice at the foot of the screen now.
    ///
    /// WHY THE ONBOARDING LINE IS SHORTER THAN IT WAS: it said "…but much more slowly" (the
    /// cost of a backgrounded transfer, decided 2026-10-09). The validated #708 brief and
    /// mock-up give the line as "The download continues if you leave the app.", and the
    /// shorter line still reads at a glance at the foot of the lot 1.1 screen.
    private func leaveNotice(isDownloading: Bool) -> Text {
        switch activeContext.leaveNotice(isDownloading: isDownloading) {
        case .downloadContinuesInBackground:
            return Text("The download continues if you leave the app.", comment: "Onboarding model preparation, while downloading (#675, #708).")
        case .waitForPreparation:
            return Text("Please wait for preparation to finish.")
        case .stayOnPage:
            return Text("Please stay on this page and do not leave the app.")
        }
    }

    // MARK: - Phase logic

    /// The phase the screen draws: the completion once it has been decided, otherwise the
    /// current work phase, holding the last one through the frame where the model state
    /// already reads ready but `checkForCompletion` has not run yet.
    private var displayedPhase: Phase {
        if showCompletion { return .ready }
        let phase = currentPhase
        return phase == .ready ? lastWorkPhase : phase
    }

    /// Starts the percentage's clock for the compile or the load, and the countdown's when
    /// it applies, once each.
    private func startClocksIfWorking() {
        if preparationSeenAt == nil, rawPhase == .compiling || rawPhase == .loading {
            preparationSeenAt = Date()
        }
        anchorCountdownIfCold()
    }

    /// Starts the countdown's clock, once, if this preparation deserves one (issue #533).
    ///
    /// WHY WARMTH IS PART OF IT: an ordinary launch with a warm Core ML cache also goes
    /// through `.loading`, for about three seconds. Without this check every warm load
    /// would flash "About 4 minutes left". `ModelWarmth` is false exactly when the cache is
    /// cold, and it answers `true` when the install identity cannot be read — here that
    /// means "no countdown", the safe direction.
    ///
    /// WHY ONLY `.minutes`: `.brief` (Medium's 32 s) would only ever show "Less than a
    /// minute left"; `.unmeasured` has nothing to count down from.
    ///
    /// WHY `rawPhase` AND NOT THE PHASE ON SCREEN (#708): a model already on disk is drawn
    /// as optimizing from the first frame, before any work has started — and when that
    /// model turns out to be loaded already, no work ever starts. The clock waits for the
    /// model's state to say a compile or a load is really running.
    ///
    /// Warmth is read here, when the anchor is decided, and never on a tick: by the time
    /// the warm inference records the model as warm, the screen is on its way out.
    private func anchorCountdownIfCold() {
        guard preparationStartedAt == nil,
              rawPhase == .compiling || rawPhase == .loading,
              !loadGaveUp,
              !showCompletion,
              case .minutes = ModelPreparationWait.forModel(modelIdentifier) else {
            return
        }
        let identity = ModelWarmth.installIdentity(
            bundlePathComponents: Bundle.main.bundleURL.pathComponents,
            systemVersion: UIDevice.current.systemVersion
        )
        guard !ModelWarmth.isWarm(modelIdentifier, identity: identity) else { return }
        preparationStartedAt = Date()
    }

    private var currentModelState: ModelState {
        modelManager.modelStates[modelIdentifier] ?? .notDownloaded
    }

    /// The phase, with the opening frame decided by `ModelPreparationPhase.displayed`:
    /// before any work has been seen, a resting state is drawn as the work about to start
    /// (the download, or the optimization for a model already on disk) rather than as done.
    /// This is the seam that fixes the onboarding presentation race (commit f5ba7ab
    /// follow-up) and the download that did not happen (#708).
    private var currentPhase: Phase {
        Phase.displayed(raw: rawPhase, hasSeenWorkPhase: hasSeenWorkPhase, filesOnDisk: filesOnDiskAtOpen)
    }

    private var rawPhase: Phase {
        switch currentModelState {
        case .downloading:
            return .downloading
        case .prewarming:
            return .compiling
        case .ready:
            switch modelManager.modelLoadState {
            case .loading:
                return .loading
            case .ready:
                return .ready
            case .idle:
                // Defensive: model is ready on disk but no load is in flight.
                // Treat as ready so the overlay can dismiss.
                return .ready
            }
        case .notDownloaded, .error:
            return .ready
        }
    }

    private func checkForCompletion() {
        // A failed download must dismiss the cover immediately — without this,
        // `.error` falls into rawPhase's `.ready` mapping below and flashes the
        // "Model ready" celebration on a failure (issue #207). The parent view
        // surfaces the error message once the cover is gone.
        if case .error = currentModelState {
            isPresented = false
            return
        }
        // Latch the work-phase flag the first time we observe real activity.
        // We read `rawPhase` here (not the user-facing `currentPhase`) because
        // the latter masquerades the initial `.ready` state as a work phase
        // until this flag flips, which would cause an infinite loop.
        if rawPhase != .ready {
            hasSeenWorkPhase = true
            return
        }
        // The model is ready, but if we have never seen any actual work happen
        // yet, the parent likely just opened the overlay and the state will
        // imminently flip to `.downloading`. Keep the cover up.
        //
        // The one exception — a preparation asked for a model that genuinely is loaded
        // already — is `ModelPreparationOutcome`'s to decide, in OuisprCore where it is
        // tested. What it needs and this line used to omit is whether anything alive in
        // this launch wrote the load state at all (#579): read at `onAppear` on a launch
        // from dead, it is the previous process's, and every part of it is false.
        let preparationWasAlreadyReady = ModelPreparationOutcome.preparationWasAlreadyReady(
            context: activeContext,
            isModelOnDisk: currentModelState == .ready,
            loadState: modelManager.modelLoadState,
            loadStateIsFromThisLaunch: modelManager.loadStateIsFromThisLaunch
        )
        guard hasSeenWorkPhase || preparationWasAlreadyReady else {
            return
        }
        guard !showCompletion else { return }

        // Nothing to celebrate: the app gave up on this load, the compile is still
        // running, and no engine arrived. Leave without the checkmark (finding D).
        guard !loadGaveUp else {
            isPresented = false
            return
        }

        // No `withAnimation` here: the content animates its own phase change in place
        // (`content`), and the eyes time their own passage (lot 1.1). A transaction
        // around this flag used to drive a scale transition between two layouts.
        showCompletion = true

        // The ready state holds for a moment, then the screen dismisses itself and the
        // onboarding moves on by itself (#708: no Continue button).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: Motion.emphasized)) {
                isPresented = false
            }
        }
    }
}

#Preview("Downloading — light") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["parakeet-tdt-0.6b-v3"] = .downloading
            m.downloadProgress["parakeet-tdt-0.6b-v3"] = 0.34
            return m
        }(),
        modelIdentifier: "parakeet-tdt-0.6b-v3",
        context: .onboarding,
        isPresented: .constant(true)
    )
    .preferredColorScheme(.light)
}

#Preview("Compiling — dark") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3-v20240930_turbo_632MB"] = .prewarming
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3-v20240930_turbo_632MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
