// OuisprApp/Views/HomeView.swift
// Home: the character, the mode under it, the three latest dictations, the mic, and the settings.
import SwiftUI
import OuisprCore

/// Home — the app's single screen, and the first one users see after onboarding.
///
/// « Banc Ouispr épuré » (Alex, 27 Nov 2026), top to bottom: the settings (top right);
/// the character, and under it the mode of the next dictation, which is the button that
/// changes it; « Récentes », the three latest dictations as flat rows, with « Tout voir »
/// for the history; the ink mic. Nothing on it moves but the character: the background is
/// a still veil (`OuisprBackdrop`), the rows stay where they are.
///
/// The history is not Home: it opens from « Tout voir » or a swipe up (#70), and has no
/// mic of its own. One dictates from here.
struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @EnvironmentObject var history: TranscriptionHistoryStore
    @ObservedObject var modelManager: ModelManager

    /// Raises the model preparation screen when a tap arrives during a load (#484).
    @Environment(\.presentModelPreparation) private var presentModelPreparation

    /// The sheet on screen, if any: the history (#70), the settings, the models or a
    /// recent dictation.
    ///
    /// WHY one optional and not a Boolean per sheet: two Booleans can both be true,
    /// and SwiftUI presents one sheet per view. An optional cannot name two.
    @State private var sheet: HomeSheet?

    /// What the settings button, « Tout voir », a recent row and the "no model" card
    /// can open.
    private enum HomeSheet: Identifiable {
        case history
        case settings
        case models
        case record(TranscriptionRecord)

        var id: String {
            switch self {
            case .history: return "history"
            case .settings: return "settings"
            case .models: return "models"
            case .record(let record): return "record.\(record.id)"
            }
        }
    }

    /// Drives the Ouispr Pro hub: from the Pro banner, the mode menu's Ouispr Pro row, or
    /// a locked history. One cover on a view that never leaves the screen (#216).
    @State private var showPaywall = false

    /// What the mode button says: whether modes are offered, and which mode the next
    /// dictation runs (#489). A copy of the App Group, refreshed by `refreshSmartMode()`
    /// rather than read per body evaluation, because the keyboard writes it from another
    /// process and nothing publishes that write.
    @State private var smartModeMic = SmartModeHomeMic(isOffered: false, effectiveMode: nil)

    /// The mode menu's rows, read with `smartModeMic` so the menu opens on what the App
    /// Group says now. Nil when modes are not offered.
    @State private var modePicker: SmartModeHomePicker?

    /// The default mode's identifier, as the menu's « Mode par défaut » says it.
    @State private var defaultModeID: String?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether a sheet or a cover hides this screen, which pauses the character.
    @ObservedObject private var sphereCover = SphereCover.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Observed so a Smart Mode switch flipped in the Pro hub moves the mode button on
    /// the way back here: the switch writes the App Group, which publishes nothing.
    @ObservedObject private var switches = ProFeatureSwitches.shared

    /// What the history offers this user (#70): open, locked (the Pro window), or
    /// absent while the paywall is unreachable.
    ///
    /// Read through `proStatus.isProActive` first so SwiftUI actually re-renders:
    /// `FeatureGate` goes straight to the App Group, which publishes nothing.
    private var entryPoint: HistoryEntryPoint {
        _ = proStatus.isProActive
        return HistoryAvailability.entryPoint
    }

    /// How far up the finger has to travel before the history opens.
    ///
    /// WHY 60pt and not the 20pt that would already register as a drag: this gesture
    /// sits over the whole dashboard, including buttons and cards. A short flick while
    /// reaching for one of them must not open another screen.
    private let swipeUpThreshold: CGFloat = 60

    var body: some View {
        VStack(spacing: 16) {
            topBar

            // The content scrolls only when nothing else fits: an iPhone SE, a large
            // Dynamic Type. The Pro card goes first, then the scroll.
            //
            // WHY `ViewThatFits` and not a permanent ScrollView: a scroll view takes
            // every vertical drag that starts on it, which would take the swipe up to
            // the history (#70) away from most of the screen.
            ViewThatFits(in: .vertical) {
                // Hung from the top, not centred: a third dictation adds a row under the
                // others and moves nothing above it.
                dashboard(showsProCard: true)
                    .frame(maxHeight: .infinity, alignment: .top)
                dashboard(showsProCard: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                ScrollView {
                    dashboard(showsProCard: false)
                }
            }

            // The primary action, at the bottom: within thumb reach, and where the
            // recording screen's mic leaves from and comes back to (#788).
            if modelManager.isModelReady {
                newDictationButton
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
        }
        // The system's margins (16 pt on most iPhones), not a value of Home's own.
        .scenePadding(.horizontal)
        .padding(.top, 8)
        .background(OuisprBackdrop())
        // Home pushes nothing and has no title: an empty navigation bar would only
        // take 44 pt from the top of the app's single screen.
        .toolbar(.hidden, for: .navigationBar)
        // The swipe up to the history. `.gesture` and not `.simultaneousGesture`: a
        // simultaneous drag would fire alongside the buttons underneath instead of
        // losing to their taps. With `minimumDistance` set, a tap never reaches here.
        // Off where it leads nowhere.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // The predicted end is what makes a fast flick work.
                    let travelled = min(value.translation.height, value.predictedEndTranslation.height)
                    guard travelled < -swipeUpThreshold else { return }
                    openHistory()
                },
            including: entryPoint == .hidden ? .none : .all
        )
        .sheet(item: $sheet, onDismiss: {
            // Coming back from a sheet does not re-fire `onAppear`, and the models and
            // the settings are where the model, the modes and the default change.
            modelManager.loadState()
            refreshSmartMode()
        }, content: { presented in
            Group {
                switch presented {
                case .history:
                    // The store is handed over explicitly: a sheet is presented from a
                    // different part of the view tree.
                    HistoryView()
                        .environmentObject(history)
                        .environmentObject(proStatus)
                case .settings:
                    secondarySheet {
                        SettingsView(modelManager: modelManager)
                    }
                    .environmentObject(history)
                    .environmentObject(proStatus)
                case .models:
                    secondarySheet {
                        ModelManagerView(modelManager: modelManager)
                    }
                case .record(let record):
                    // A recent row opens the dictation's own screen, as in the history.
                    secondarySheet {
                        if record.source == .sharedFile {
                            VoiceNoteResultView(noteID: record.id)
                        } else {
                            TranscriptionDetailView(record: record)
                        }
                    }
                }
            }
            // While a sheet is up, Home's character is hidden: it stops drawing.
            .coversHomeSphere()
        })
        .paywallCover(isPresented: $showPaywall, entry: .feature(.smartMode))
        .onAppear {
            modelManager.loadState()
            refreshSmartMode()
        }
        // The keyboard arms modes from another app, so the change lands while this
        // screen is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSmartMode() }
        }
        // A reason that clears by itself (Apple Intelligence downloading, or busy) is
        // re-read every 30 s while Home is up: the menu builds its rows from the last
        // read, and nothing announces the moment the reason goes.
        .task(id: modePicker?.unavailableReason) {
            while let reason = modePicker?.unavailableReason,
                  reason == .modelNotReady || reason == .engineRefusing {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                refreshSmartMode()
            }
        }
        .onChange(of: proStatus.isProActive) { _, _ in refreshSmartMode() }
        .onChange(of: switches.values) { _, _ in refreshSmartMode() }
        // Back from a dictation: the mode has returned to its default
        // (`DictationCoordinator`).
        .onChange(of: coordinator.status) { _, status in
            guard status == .idle else { return }
            refreshSmartMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OuisprOnboardingCompleted"))) { _ in
            // HomeView mounts behind the onboarding cover, so onAppear fires before the
            // model is downloaded, and does not fire again when the cover goes.
            modelManager.loadState()
        }
    }

    // MARK: - Top Bar

    /// The settings, top right: a glass circle of 44 pt, the screen's one control up
    /// there. The mode is said and chosen under the character (`HomeModeMenu`).
    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .frame(width: 44, height: 44)
                    .ouisprGlass(in: Circle())
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
        }
        .frame(height: 44)
    }

    /// A settings-style screen in a sheet: its own navigation stack, a close button,
    /// and the grabber that says it can be dragged down.
    private func secondarySheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                // Inline: a large title scrolled up under the leading close button
                // before collapsing, and read "⌄glages" for a moment (audit, 22 Nov 2026,
                // finding 9). Tried large again for the « version épurée » (27 Nov 2026):
                // under the opaque bar below, the large title drew washed out at rest on
                // iOS 26.3. A sheet with a close button carries its title in the bar.
                .navigationBarTitleDisplayMode(.inline)
                // A bar that hides what scrolls under it: through the light material
                // the rows stayed readable behind the title (audit of 26 Nov 2026, n°17).
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.ouisprBackground.opacity(0.94), for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            sheet = nil
                        } label: {
                            // Its own ink and weight: left to the bar's tint, the glyph
                            // vanished and the button read as an empty white circle.
                            Image(systemName: "chevron.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.ouisprTextPrimary)
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Dashboard

    /// The character, the mode, the recent dictations and, where it fits, the Pro card.
    private func dashboard(showsProCard: Bool) -> some View {
        VStack(spacing: 16) {
            character

            if modelManager.isModelReady {
                readySection
            } else {
                modelPromptCard
            }

            let recent = recentRecords
            if !recent.isEmpty {
                recentSection(recent)
                    .padding(.top, 8)
            }

            // The Home Pro card: the offer, the trial reminder, or a subscriber's way
            // into the hub (#216 decision 16). Only where the screen has room for it.
            if showsProCard && PremiumFlags.paywallVisible {
                ProBannerView { showPaywall = true }
            }
        }
    }

    /// The app's face. While a dictation is up, the recording screen carries this same
    /// character (`sharesMotion`) on this very spot (`HomeSphereAnchor`); this copy is
    /// then hidden and paused, so the two are never seen at once.
    ///
    /// Drawn in a 240 pt square (Alex's 1A, the bench's character 20 % larger) laid out
    /// 180 pt tall: the ink is 160 × 120 pt in the middle of the square, so the 30 pt
    /// above and below it are empty and give their room to the mode and the list. The
    /// recording screen knows this overlap (`RecordingView.homeHeadingGap`).
    private var character: some View {
        let side: CGFloat = dynamicTypeSize.isAccessibilitySize ? 160 : 240
        let away = coordinator.status != .idle
        return InkCharacterView(
            mood: .resting,
            isPaused: away || sphereCover.isCovered,
            isAmbient: true,
            sharesMotion: true
        )
        .frame(width: side, height: side)
        .reportsHomeSphere()
        .opacity(away ? 0 : 1)
        // No animation: the hand-over back is invisible only because the recording
        // screen's character has just landed on this spot. Reduce Motion has no flight,
        // so there this one fades back in instead of popping.
        .animation(reduceMotion ? .easeOut(duration: Motion.standard) : nil, value: away)
        .frame(height: side * 0.75)
    }

    // MARK: - Ready Section

    /// Under the character: the mode the next dictation runs, which is also the button
    /// that changes it, or, where modes are not offered, the one sentence that says how.
    private var readySection: some View {
        VStack(spacing: 8) {
            Group {
                if let modePicker {
                    HomeModeMenu(
                        picker: modePicker,
                        mode: smartModeMic.effectiveMode,
                        defaultIdentifier: defaultModeID,
                        onChoose: choose,
                        onSetDefault: setDefault
                    )
                } else {
                    Text("Tap the mic and speak.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.ouisprTextSecondary)
                }
            }
            // One height either way, so the list under it never moves.
            .frame(minHeight: 44)
            // During the reverse trial, the one indicator it gets on this screen
            // (#593): discreet, never a nag.
            if let daysLeft = proStatus.trialBadgeDaysLeft {
                ProTrialBadge(daysLeft: daysLeft)
            }
        }
        .multilineTextAlignment(.center)
        // Gone as soon as a dictation starts, before the recording screen writes its
        // stage on this same line, and back only once that screen has left: the two
        // never show at once (Beta 45 feedback, 25 Nov 2026).
        .opacity(coordinator.status == .idle ? 1 : 0)
        .animation(.easeOut(duration: Motion.quick), value: coordinator.status == .idle)
    }

    // MARK: - Recent dictations

    /// The latest three dictations with words, without the repeats that follow each other.
    private var recentRecords: [TranscriptionRecord] {
        Array(DictationList.shown(history.records) { $0.text }.prefix(DictationList.homeCount))
    }

    /// « Récentes » with « Tout voir », then the three latest dictations as flat rows on
    /// one plain surface (« Banc Ouispr épuré », 27 Nov 2026). Nothing moves: a new
    /// dictation is a new first row, there when the recording screen leaves.
    private func recentSection(_ records: [TranscriptionRecord]) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if entryPoint != .hidden {
                    Button("See all", action: openHistory)
                        .font(.body)
                        .foregroundStyle(Color.ouisprAccentText)
                        // Apple's 44 pt minimum touch target.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("home.history")
                }
            }
            .frame(minHeight: 44)

            VStack(spacing: 0) {
                ForEach(records) { record in
                    if record.id != records.first?.id {
                        Divider().padding(.leading, 16)
                    }
                    Button {
                        sheet = .record(record)
                    } label: {
                        DictationRow(record: record)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.recent.\(record.id)")
                }
            }
            // Flat: a plain surface, the glass is for the controls (contrôle V1.1).
            .background(Color.ouisprSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func openHistory() {
        switch entryPoint {
        case .open: sheet = .history
        case .locked: showPaywall = true
        case .hidden: break
        }
    }

    // MARK: - Model Prompt Card

    /// Without a model the app cannot transcribe, and there is no mic to tap: this
    /// card is then the screen's one action, and it opens the models.
    private var modelPromptCard: some View {
        Button {
            sheet = .models
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.ouisprAccentText)
                Text("Download a model to get started")
                    .font(.ouisprSubheading)
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .multilineTextAlignment(.center)
                    // Wraps instead of truncating at the largest text sizes.
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose a model")
                    .font(.ouisprBody)
                    .foregroundColor(.ouisprAccentText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .ouisprGlass()
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityIdentifier("home.chooseModel")
    }

    // MARK: - New Dictation Button

    /// The ink mic that starts a dictation, only shown when a model is ready: a plain
    /// disc, the mode being the button's under the character.
    ///
    /// WHY a button that starts dictation instead of a NavigationLink to TestDictationView:
    /// MainTabView shows a RecordingView overlay when coordinator.status != .idle, and a
    /// pushed screen would stack a second one under it.
    private var newDictationButton: some View {
        InkMicButton(phase: .resting) {
            startDictation()
        }
        // VoiceOver hears the mode the dictation will run as the value (#397).
        .accessibilityLabel("New dictation")
        .accessibilityValue(smartModeMic.isOffered
                            ? Text(HomeSmartModeCopy.name(of: smartModeMic.effectiveMode))
                            : Text(verbatim: ""))
        .accessibilityIdentifier("home.newDictation")
        // The recording screen's mic leaves from here and comes back here (#788).
        .reportsPrimaryMicAnchor()
    }

    /// A tap on the mic.
    private func startDictation() {
        // A tap that lands during a model load gets the preparation screen instead of
        // being swallowed by `startDictation`'s guard (#484). The button stays live and
        // keeps its shape: `isModelReady` above says a model is on disk and elected, which
        // is a different question from whether one is loading right now.
        switch coordinator.recordTapDecision {
        case .presentPreparation:
            presentModelPreparation()
        case .startDictation:
            coordinator.startDictation(origin: .app)
        }
    }

    // MARK: - Mode menu

    /// Re-read what the mode button shows from the App Group, and the menu's rows with it.
    ///
    /// WHY here and not when the menu opens: a system menu builds its rows from the
    /// body, with no moment of its own to read the App Group. Read on appear, on the way
    /// back to the foreground and after each change, which is when the keyboard, the Pro
    /// hub or a dictation can have moved it; this also keeps `SystemLanguageModel` off
    /// every body pass.
    private func refreshSmartMode() {
        smartModeMic = SmartModeHomeMic.current
        defaultModeID = SmartModeDefault.identifier
        modePicker = smartModeMic.isOffered ? SmartModeHomePicker.current() : nil
    }

    /// A row of the menu: arm it (Normal disarms), or open the Pro window.
    private func choose(_ entry: SmartModeFanEntry) {
        guard let picker = SmartModeHomePicker.current() else { return }
        switch picker.choose(entry) {
        case .openPaywall:
            showPaywall = true
        case .armed, .disarmed:
            HapticFeedback.keyTapped()
            refreshSmartMode()
        case .refused:
            HapticFeedback.actionRefused()
        }
        PersistentLog.log(.diagnosticProbe(
            component: "HomeView", instanceID: "-", action: "smartModeChosen",
            details: "row=\(entry.id) source=homeMenu"
        ))
    }

    /// « Mode par défaut » in the menu: the mode becomes the default the app returns to
    /// after each dictation, and the mode of the next one too.
    private func setDefault(_ entry: SmartModeFanEntry) {
        HapticFeedback.keyTapped()
        SmartModeDefault.set(entry.smartMode)
        SmartModeDefault.returnToDefault()
        refreshSmartMode()
    }
}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
            .environmentObject(ProStatusManager())
            .environmentObject(TranscriptionHistoryStore.shared)
    }
}
