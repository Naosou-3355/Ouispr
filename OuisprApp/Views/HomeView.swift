// OuisprApp/Views/HomeView.swift
// Home: the character, the five latest dictations drifting in two rows, the mic, and the mode and settings buttons.
import SwiftUI
import OuisprCore

/// Home — the app's single screen, and the first one users see after onboarding.
///
/// « Fiche historique et accueil V1 » (Alex, 24-25 Nov 2026), top to bottom: the mode of
/// the next dictation (top left) and the settings (top right); the character and
/// « Prêt à dicter »; « Récentes », the last five dictations as glass cards in two rows
/// drifting opposite ways, with « Tout voir » for the history; the ink mic. A dictation
/// that lands comes out of the character and slides to the head of the first row.
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

    /// The sheet on screen, if any: the history (#70), the settings or the models.
    ///
    /// WHY one optional and not a Boolean per sheet: two Booleans can both be true,
    /// and SwiftUI presents one sheet per view. An optional cannot name two.
    @State private var sheet: HomeSheet?

    /// What the two buttons at the top, « Tout voir » and the "no model" card can open.
    private enum HomeSheet: String, Identifiable {
        case history
        case settings
        case models

        var id: String { rawValue }
    }

    /// Drives the Ouispr Pro hub: from the Pro banner, the mode menu's Ouispr Pro row, or
    /// a locked history. One cover on a view that never leaves the screen (#216).
    @State private var showPaywall = false

    /// What the mode button says: whether modes are offered, and which mode the next
    /// dictation runs (#489). A copy of the App Group, refreshed by `refreshSmartMode()`
    /// rather than read per body evaluation, because the keyboard writes it from another
    /// process and nothing publishes that write.
    @State private var smartModeMic = SmartModeHomeMic(isOffered: false, effectiveMode: nil)

    /// The mode menu while it is open.
    @State private var modeMenu: SmartModeHomePicker?

    /// The default mode's identifier, as the menu and the line under « Prêt à dicter » say it.
    @State private var defaultModeID: String?

    /// The five cards on show. Trails `history.records` while a dictation is up, so the
    /// new card arrives once Home can be seen again rather than behind the recording screen.
    @State private var recent: [TranscriptionRecord] = []

    /// A card on its way out of the character to the head of the first row.
    @State private var arrival: Arrival?

    /// The card lifted open, if any.
    @State private var openedCard: OpenedCardState?

    /// The first row's frame in window coordinates: where an arriving card lands.
    @State private var firstRowFrame: CGRect = .zero
    /// Where the first row draws the arriving card, once it has laid it out.
    @State private var arrivalTarget: CGRect?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether a sheet or a cover hides this screen, which pauses the character.
    @ObservedObject private var sphereCover = SphereCover.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Where the character is, which an arriving card leaves from.
    @ObservedObject private var homeSphere = HomeSphereAnchor.shared

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
                dashboard(showsProCard: true)
                    .frame(maxHeight: .infinity)
                dashboard(showsProCard: false)
                    .frame(maxHeight: .infinity)
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
        .padding()
        // The mist stops while a sheet or the paywall covers Home. Not under the recording
        // screen: that screen fades out over it, and both mists, read off the clock, are
        // then in the same place; a paused one would jump as it resumed.
        .background(OuisprMist(isPaused: sheet != nil || showPaywall))
        // Home pushes nothing and has no title: an empty navigation bar would only
        // take 44 pt from the top of the app's single screen.
        .toolbar(.hidden, for: .navigationBar)
        .overlay { arrivingCard }
        .overlay { openedCardOverlay }
        .overlay(alignment: .topLeading) { modeMenuOverlay }
        // The swipe up to the history. `.gesture` and not `.simultaneousGesture`: a
        // simultaneous drag would fire alongside the buttons underneath instead of
        // losing to their taps. With `minimumDistance` set, a tap never reaches here.
        // Off where it leads nowhere, and while a card or the menu is open.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // The predicted end is what makes a fast flick work.
                    let travelled = min(value.translation.height, value.predictedEndTranslation.height)
                    guard travelled < -swipeUpThreshold else { return }
                    openHistory()
                },
            including: entryPoint == .hidden || openedCard != nil || modeMenu != nil ? .none : .all
        )
        .sheet(item: $sheet, onDismiss: {
            // Coming back from a sheet does not re-fire `onAppear`, and the models and
            // the settings are where the model, the modes and the default change.
            modelManager.loadState()
            refreshSmartMode()
            updateRecent(animated: false)
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
                }
            }
            // While a sheet is up, Home's character is hidden: it stops drawing.
            .coversHomeSphere()
        })
        .paywallCover(isPresented: $showPaywall, entry: .feature(.smartMode))
        .onAppear {
            modelManager.loadState()
            refreshSmartMode()
            updateRecent(animated: false)
        }
        // The keyboard arms modes from another app, so the change lands while this
        // screen is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSmartMode() }
        }
        .onChange(of: proStatus.isProActive) { _, _ in refreshSmartMode() }
        .onChange(of: switches.values) { _, _ in refreshSmartMode() }
        // Back from a dictation: the mode has returned to its default
        // (`DictationCoordinator`), and the new card comes out of the character.
        .onChange(of: coordinator.status) { _, status in
            guard status == .idle else { return }
            refreshSmartMode()
            updateRecent(animated: true)
        }
        .onChange(of: history.records) { _, _ in
            if coordinator.status == .idle && sheet == nil { updateRecent(animated: false) }
        }
        .onDisappear { modeMenu = nil }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OuisprOnboardingCompleted"))) { _ in
            // HomeView mounts behind the onboarding cover, so onAppear fires before the
            // model is downloaded, and does not fire again when the cover goes.
            modelManager.loadState()
        }
    }

    // MARK: - Top Bar

    /// The mode of the next dictation on the left, the settings on the right: two glass
    /// circles, 44 pt.
    private var topBar: some View {
        HStack {
            if smartModeMic.isOffered {
                // Removed while the menu stands in its place, not faded to 0: a glass view
                // brought back from zero opacity could stay invisible after the menu closed
                // (audit of 26 Nov 2026, n°7). The empty frame keeps the bar's layout.
                if modeMenu == nil {
                    HomeModeButton(mode: smartModeMic.effectiveMode) { openModeMenu() }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
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
                // Inline, like History: a large title scrolled up under the leading
                // close button before collapsing, and read "⌄glages" for a moment
                // (audit, 22 Nov 2026, finding 9). A sheet with a close button carries
                // its title in the bar from the start.
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

    /// The character, what it says, the recent cards and, where it fits, the Pro card.
    private func dashboard(showsProCard: Bool) -> some View {
        VStack(spacing: 16) {
            character

            if modelManager.isModelReady {
                readySection
            } else {
                modelPromptCard
            }

            if !recent.isEmpty {
                recentSection
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
    /// above and below it are empty and give their room to the recent cards. The
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

    /// « Prêt à dicter », and under it the mode the next dictation runs, or the one
    /// sentence that says how.
    private var readySection: some View {
        VStack(spacing: 8) {
            Text("Ready to dictate")
                .font(.ouisprHeading)
                .foregroundStyle(Color.ouisprTextPrimary)
            Group {
                if let mode = smartModeMic.effectiveMode {
                    HomeModeLine(mode: mode, isDefault: mode.id == defaultModeID)
                } else {
                    Text("Tap the mic and speak.")
                        .font(.ouisprBody)
                        .foregroundStyle(Color.ouisprTextSecondary)
                }
            }
            .frame(minHeight: 22)
            // During the reverse trial, the one indicator it gets on this screen
            // (#593): discreet, never a nag.
            if let daysLeft = proStatus.trialBadgeDaysLeft {
                ProTrialBadge(daysLeft: daysLeft)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        // Gone as soon as a dictation starts, before the recording screen writes its
        // stage on this same line, and back only once that screen has left: the two
        // never show at once (Beta 45 feedback, 25 Nov 2026).
        .opacity(coordinator.status == .idle ? 1 : 0)
        .animation(.easeOut(duration: Motion.quick), value: coordinator.status == .idle)
    }

    // MARK: - Recent cards

    /// « Récentes » with « Tout voir », then the five latest dictations: three cards,
    /// then two, drifting opposite ways.
    private var recentSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Recent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ouisprTextPrimary)
                Spacer()
                if entryPoint != .hidden {
                    Button("See all", action: openHistory)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ouisprAccent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("home.history")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 4)

            VStack(spacing: DictationCloudCard.gap) {
                ForEach(Array(DictationCloud.homeRows(recent).enumerated()), id: \.offset) { index, row in
                    DriftingCardRow(
                        records: row,
                        direction: index == 0 ? -1 : 1,
                        speedFactor: index == 0 ? 1 : 0.8,
                        isPaused: isDriftPaused,
                        openID: openedCard?.record.id ?? arrival?.record.id,
                        onOpen: { record, frame in open(record, from: frame) },
                        onOpenCardFrame: { frame in
                            // A looping row draws its cards more than once: the copy on
                            // screen is the one the new card lands on.
                            guard index == 0, arrival != nil,
                                  frame.minX >= -1, frame.maxX <= firstRowFrame.maxX + 1 else { return }
                            arrivalTarget = frame
                        }
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        if index == 0 { firstRowFrame = frame }
                    }
                }
            }
            // The cards run to the screen's edges, past Home's 16 pt margins.
            .padding(.horizontal, -16)
        }
    }

    /// The drift stops while anything else holds the eye: a dictation, a sheet, an open
    /// card or the menu.
    private var isDriftPaused: Bool {
        // Held while a new card flies in, so it lands where its row will draw it.
        // And while a sheet or the paywall hides Home: nothing on screen to draw.
        coordinator.status != .idle || sphereCover.isCovered || openedCard != nil || modeMenu != nil
            || arrival != nil || sheet != nil || showPaywall
    }

    /// Show the latest five. A new head card arrives from the character when `animated`.
    /// The character's drop is played on the recording screen, over the result (audit of
    /// 26 Nov 2026), so the card leaves a character already at rest.
    private func updateRecent(animated: Bool) {
        let worded = history.records.filter { !DictationCloud.title(for: $0.text).isEmpty }
        let latest = Array(DictationCloud.droppingRepeats(worded) { $0.text }.prefix(5))
        guard latest.map(\.id) != recent.map(\.id) else {
            recent = latest
            return
        }
        let isNew = latest.first.map { head in !recent.contains { $0.id == head.id } } ?? false
        guard animated, isNew, !recent.isEmpty, let head = latest.first, let from = homeSphere.homeFrame else {
            recent = latest
            return
        }
        // The flying card carries its words from the start: a chip never travels empty
        // and fills on landing (audit of 26 Nov 2026, n°3).
        RevealedTitles.markSeen(head.id)
        arrivalTarget = nil
        recent = latest
        arrival = Arrival(record: head, from: CGPoint(x: from.midX, y: from.midY))
    }

    /// The card coming out of the character, drawn over the screen until it lands on
    /// the first row's head, where its row draws it from then on.
    @ViewBuilder
    private var arrivingCard: some View {
        if let arrival {
            GeometryReader { geo in
                let space = geo.frame(in: .global)
                let card = DictationCloudCard(record: arrival.record)
                // Where the row draws it; until the row has laid it out, a first row's
                // head, 14 pt inside the screen's edge (`DriftEngine`).
                let target = arrivalTarget.map { CGPoint(x: $0.midX, y: $0.midY) }
                    ?? CGPoint(x: firstRowFrame.minX + 14 + card.width / 2, y: firstRowFrame.midY)
                ArrivingCard(record: arrival.record,
                             from: CGPoint(x: arrival.from.x - space.minX, y: arrival.from.y - space.minY),
                             to: CGPoint(x: target.x - space.minX, y: target.y - space.minY)) {
                    self.arrival = nil
                    self.arrivalTarget = nil
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }

    // MARK: - Opened card

    @ViewBuilder
    private var openedCardOverlay: some View {
        if let openedCard {
            OpenedDictationCard(record: openedCard.record, origin: openedCard.origin) {
                self.openedCard = nil
            }
            .ignoresSafeArea()
        }
    }

    private func open(_ record: TranscriptionRecord, from frame: CGRect) {
        HapticFeedback.keyTapped()
        openedCard = OpenedCardState(record: record, origin: frame)
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
                    .foregroundColor(.ouisprAccent)
                Text("Download a model to get started")
                    .font(.ouisprSubheading)
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .multilineTextAlignment(.center)
                    // Wraps instead of truncating at the largest text sizes.
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose a model")
                    .font(.ouisprBody)
                    .foregroundColor(.ouisprAccent)
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
    /// disc, the mode being the button's at the top left.
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

    /// Re-read what the mode button shows from the App Group.
    private func refreshSmartMode() {
        smartModeMic = SmartModeHomeMic.current
        defaultModeID = SmartModeDefault.identifier
    }

    /// Resolved at open: armability cannot change while the menu is up, and reading it
    /// once keeps `SystemLanguageModel` off every body pass.
    private func openModeMenu() {
        guard let picker = SmartModeHomePicker.current() else { return }
        HapticFeedback.keyTapped()
        modeMenu = picker
    }

    @ViewBuilder
    private var modeMenuOverlay: some View {
        if let modeMenu {
            HomeModeMenu(
                picker: modeMenu,
                defaultIdentifier: defaultModeID,
                onChoose: choose,
                onSetDefault: setDefault,
                onClose: { self.modeMenu = nil }
            )
            // On the button's own corner: Home's 16 pt margin.
            .padding(16)
        }
    }

    /// A row of the menu: arm it (Normal disarms), or open the Pro window.
    private func choose(_ entry: SmartModeFanEntry) {
        modeMenu = nil
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

    /// A long press on a row: it becomes the default the app returns to after each
    /// dictation, and the mode of the next one too.
    private func setDefault(_ entry: SmartModeFanEntry) {
        SmartModeDefault.set(entry.smartMode)
        SmartModeDefault.returnToDefault()
        refreshSmartMode()
        if let picker = SmartModeHomePicker.current() { modeMenu = picker }
    }
}

/// A card leaving the character for the first row.
private struct Arrival: Equatable {
    let record: TranscriptionRecord
    let from: CGPoint
}

/// The arriving card's flight: from the character's middle, small and transparent, to
/// the first row's head, on the cards' spring. Reduce Motion fades it in place.
private struct ArrivingCard: View {
    let record: TranscriptionRecord
    let from: CGPoint
    let to: CGPoint
    let onLanded: () -> Void

    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let at = landed || reduceMotion ? to : from
        DictationCloudCard(record: record)
            .scaleEffect(landed || reduceMotion ? 1 : 0.3)
            .opacity(landed ? 1 : 0)
            .position(at)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: Motion.standard)
                                           : DictationCloudCard.spring) {
                    landed = true
                } completion: {
                    onLanded()
                }
            }
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
