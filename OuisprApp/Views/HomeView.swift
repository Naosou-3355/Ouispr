// OuisprApp/Views/HomeView.swift
// Home: the sphere, the mic, and two discreet ways out to the history and the settings.
import SwiftUI
import OuisprCore

/// Home — the app's single screen, and the first one users see after onboarding.
///
/// Design V2 (20 Nov 2026): one screen, one action. The sphere says the app is ready,
/// the mic starts a dictation, and everything else (history, settings, models) sits
/// behind the two icons at the top. There is no tab bar any more: `MainTabView` shows
/// this screen alone.
struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @EnvironmentObject var history: TranscriptionHistoryStore
    @ObservedObject var modelManager: ModelManager

    /// Raises the model preparation screen when a tap arrives during a load (#484).
    @Environment(\.presentModelPreparation) private var presentModelPreparation

    @State private var showCopiedFeedback = false

    /// The sheet on screen, if any: the history (#70), the settings or the models.
    ///
    /// WHY one optional and not a Boolean per sheet: two Booleans can both be true,
    /// and SwiftUI presents one sheet per view. An optional cannot name two.
    @State private var sheet: HomeSheet?

    /// What the two icons at the top, and the "no model" card, can open.
    private enum HomeSheet: String, Identifiable {
        case history
        case settings
        case models

        var id: String { rawValue }
    }

    /// Drives the Ouispr Pro hub: from the Pro banner, or when a non-subscriber
    /// reaches for the history. One cover on a view that never leaves the screen (#216).
    @State private var showPaywall = false

    /// What the home mic says about Smart Modes: whether the surface is offered, and
    /// which mode the next dictation runs (#489). A copy of the App Group, refreshed by
    /// `refreshSmartMode()` rather than read per body evaluation, because the keyboard
    /// writes it from another process and nothing publishes that write.
    @State private var smartModeMic = SmartModeHomeMic(isOffered: false, effectiveMode: nil)

    /// The rows VoiceOver's actions on the mic offer, resolved with `smartModeMic` so a
    /// body evaluation never asks Apple Intelligence anything (#489).
    @State private var smartModeChoices: SmartModeHomePicker?

    /// The open dial: one long press, from the ring opening to the release (#489).
    @State private var ringSession: SmartModeRingSession?

    /// When the last dial closed. The release of a long press can still reach the mic's
    /// button and the dashboard's swipe as a tap and a drag; neither may act on it.
    @State private var ringClosedAt: Date?

    /// Whether the mic's long-press-then-slide gesture is in flight. Resets on its own
    /// when the touch ends or is cancelled, which is how a dial whose drag never began
    /// still closes.
    @GestureState private var ringGestureActive = false

    /// The mic's frame in the dashboard's coordinate space: the drag is measured from
    /// its centre.
    @State private var micFrame: CGRect = .zero

    /// The dashboard's width, which the dial's band is sized from (#489).
    @State private var dashboardWidth: CGFloat = 0

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether a sheet or a cover hides this screen, which pauses the sphere.
    @ObservedObject private var sphereCover = SphereCover.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Observed so a Smart Mode switch flipped in the Pro hub moves the badge and the
    /// mic's face on the way back here: the switch writes the App Group, which publishes nothing.
    @ObservedObject private var switches = ProFeatureSwitches.shared

    private static let dashboardSpace = "home.dashboard"

    /// What the history offers this user (#70, corrected 2026-08-28): the feature is
    /// Pro, so the hint and the gesture are open, locked, or absent.
    ///
    /// Recomputed on every body evaluation rather than stored, and read through
    /// `proStatus.isProActive` first so SwiftUI actually re-renders: `FeatureGate`
    /// goes straight to the App Group, which publishes nothing. Without touching the
    /// observed object here, a subscription that arrived or lapsed while this screen
    /// was on show would not move the hint until something else redrew it.
    private var entryPoint: HistoryEntryPoint {
        _ = proStatus.isProActive
        return HistoryAvailability.entryPoint
    }

    /// How far up the finger has to travel before the history opens.
    ///
    /// WHY 60pt and not the 20pt that would already register as a drag: this gesture
    /// sits over the whole dashboard, including two buttons and a card. A short flick
    /// while reaching for one of them must not open another screen.
    private let swipeUpThreshold: CGFloat = 60

    var body: some View {
        VStack(spacing: 24) {
            // The two secondary destinations, as quiet as they can be while staying
            // 44 pt targets (design V2, option A).
            topBar
                .homeSmartModeRingBackdrop(ringSession != nil)

            // The content scrolls only when it does not fit: a short screen (iPhone SE,
            // or the iPhone layout an iPad runs in), a last transcription, a large
            // Dynamic Type. Since #788 the mic below is 92 pt tall with its halo, and
            // without this the content pushed it off the bottom of the screen.
            //
            // WHY `ViewThatFits` and not a permanent ScrollView: a scroll view takes
            // every vertical drag that starts on it, which would take the swipe up to
            // the history (#70) away from most of the screen. Here it exists only on
            // the screens that need it.
            ViewThatFits(in: .vertical) {
                // Centred in the space above the mic. A frame and not a `Spacer` on
                // each side: two collapsed spacers in a 24 pt stack still cost 64 pt,
                // which is what tipped an iPhone SE height into scrolling.
                dashboardCards
                    .frame(maxHeight: .infinity)
                ScrollView {
                    dashboardCards
                }
            }
            .homeSmartModeRingBackdrop(ringSession != nil)

            // The primary action, a round mic since #788. At the bottom of the content:
            // it is within thumb reach, it stays put when the last-transcription card
            // comes and goes, and it sits where the recording screen's own mic sits.
            if modelManager.isModelReady {
                micRow
                    // Room under the mic for the Smart Mode dial's release hint, which
                    // is drawn below it, on screens with no home indicator margin.
                    .padding(.bottom, 24)
            }
        }
        .padding()
        .background(Color.ouisprBackground.ignoresSafeArea())
        // Home pushes nothing and has no title: an empty navigation bar would only
        // take 44 pt from the top of the app's single screen.
        .toolbar(.hidden, for: .navigationBar)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            dashboardWidth = width
        }
        .coordinateSpace(.named(Self.dashboardSpace))
        // The swipe itself. Attached to the whole dashboard rather than to the hint,
        // because the issue asks for a swipe up "from the home screen" — the hint
        // says where, it is not the only place the gesture is allowed to start.
        //
        // `.gesture` and not `.simultaneousGesture`: a simultaneous drag would fire
        // alongside the buttons underneath instead of losing to their taps, which is
        // exactly backwards. With `minimumDistance` set, a tap never reaches here.
        //
        // Installed only when the gesture leads somewhere. On `.hidden` there is no
        // gesture at all, so nothing on this screen behaves differently for someone
        // who has never heard of the feature; on `.locked` the same swipe opens the
        // paywall, because a user who performed the gesture has asked for the thing.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // A finger sliding up from the mic to the dial's Normal sector is
                    // a 60 pt swipe up; it chose a mode, it did not ask for the history.
                    guard !isRingBusy else { return }
                    // The predicted end is what makes a fast flick work: the finger
                    // may lift after 30pt while still travelling. Either the actual
                    // or the predicted travel clearing the threshold opens the sheet.
                    let travelled = min(value.translation.height, value.predictedEndTranslation.height)
                    guard travelled < -swipeUpThreshold else { return }
                    if entryPoint == .open {
                        sheet = .history
                    } else {
                        showPaywall = true
                    }
                },
            // `.none` rather than an optional gesture: `gesture(_:)` takes a
            // concrete `Gesture`, and the mask is the API's own way to say "declared
            // but not receiving". On `.hidden` no touch on this screen reaches the
            // drag at all.
            //
            // Off as well while the Smart Mode dial is open (#489).
            including: entryPoint == .hidden || ringSession != nil ? .none : .all
        )
        .sheet(item: $sheet, onDismiss: {
            // Coming back from a sheet does not re-fire `onAppear`, and the models and
            // the settings are where the model and the Smart Modes change. Before
            // design V2 they were tabs, and returning to this one refreshed both.
            modelManager.loadState()
            refreshSmartMode()
        }, content: { presented in
            Group {
                switch presented {
                case .history:
                    // The store is handed over explicitly rather than left to the ambient
                    // environment: a sheet is presented from a different part of the view
                    // tree, and an `@EnvironmentObject` that resolves today because the root
                    // happens to publish it is a crash waiting for someone to move it.
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
            // While a sheet is up, Home's sphere is hidden: it stops drawing.
            .coversHomeSphere()
        })
        .paywallCover(isPresented: $showPaywall, entry: .feature(.smartMode))
        .onAppear {
            // Refresh model state every time HomeView appears.
            modelManager.loadState()
            refreshSmartMode()
        }
        // The keyboard arms modes from another app, so the change lands while this
        // screen is in the background. Coming back to the foreground is when the badge
        // has to catch up — the keyboard does the same on every appearance
        // (`KeyboardState.refreshFromDefaults`), which is what makes the two agree.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSmartMode() }
        }
        .onChange(of: proStatus.isProActive) { _, _ in refreshSmartMode() }
        .onChange(of: switches.values) { _, _ in refreshSmartMode() }
        // A dial left open behind another screen would come back stale.
        .onDisappear { ringSession = nil }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OuisprOnboardingCompleted"))) { _ in
            // WHY onReceive in addition to onAppear:
            // HomeView mounts behind the onboarding fullScreenCover, so onAppear fires
            // before the model is downloaded. When onboarding completes and dismisses
            // the cover, onAppear does NOT re-fire. This notification-based refresh
            // ensures HomeView shows the correct model state immediately.
            modelManager.loadState()
        }
    }

    // MARK: - Top Bar

    /// History on the left, settings on the right: two glass circles, nothing else.
    ///
    /// The history icon follows `entryPoint`, as the swipe does: open, locked (it
    /// then opens the Pro hub, because someone who tapped it asked for the feature),
    /// or absent while the paywall is unreachable (#236).
    private var topBar: some View {
        HStack {
            switch entryPoint {
            case .open:
                topBarButton(symbol: "clock", label: "History", identifier: "home.history") {
                    sheet = .history
                }
            case .locked:
                topBarButton(symbol: "clock", label: "History", identifier: "home.history") {
                    showPaywall = true
                }
            case .hidden:
                EmptyView()
            }
            Spacer()
            topBarButton(symbol: "slider.horizontal.3", label: "Settings", identifier: "home.settings") {
                sheet = .settings
            }
        }
    }

    private func topBarButton(
        symbol: String,
        label: LocalizedStringKey,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ouisprTextPrimary)
                .frame(width: 44, height: 44)
                .ouisprGlass(in: Circle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            sheet = nil
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Dashboard Cards

    /// The sphere, what it says, the last transcription and the Pro card.
    private var dashboardCards: some View {
        VStack(spacing: 24) {
            // The app's face. While a dictation is up, the recording screen carries
            // this same sphere: it draws the same simulation (`sharesMotion`) and flies
            // from this spot to its own and back (`HomeSphereAnchor`). This copy is
            // then hidden and paused, so the two are never seen at once and a hidden
            // one asks for no frames.
            // Smaller at the accessibility text sizes, so the text below keeps its
            // room (seen cut at the largest size on the design loop, 22 Nov 2026).
            let sphereSide: CGFloat = dynamicTypeSize.isAccessibilitySize ? 160 : 240
            let sphereAway = coordinator.status != .idle
            InkCharacterView(
                mood: .resting,
                // Also paused, though still drawn, under a sheet or a cover.
                isPaused: sphereAway || sphereCover.isCovered,
                sharesMotion: true
            )
                .frame(width: sphereSide, height: sphereSide)
                .reportsHomeSphere()
                .opacity(sphereAway ? 0 : 1)
                // No animation: the hand-over back is invisible only because the
                // recording screen's sphere has just landed on this spot. Reduce Motion
                // has no flight, so there this one fades back in instead of popping.
                .animation(reduceMotion ? .easeOut(duration: Motion.standard) : nil, value: sphereAway)
                // The spacing the orb had, kept so the screen below does not move.
                .padding(.vertical, 16)

            if modelManager.isModelReady {
                readySection
            } else {
                modelPromptCard
            }

            // Last transcription preview
            if let result = coordinator.lastResult {
                transcriptionCard(result: result)
            }

            // The Home Pro card: the offer, the trial reminder, or since #216 decision
            // 16 a subscriber's way into the hub. Gated behind
            // PremiumFlags.paywallVisible until the first Pro
            // feature ships and ASC setup is done (#236, #79, #215).
            if PremiumFlags.paywallVisible {
                ProBannerView { showPaywall = true }
            }
        }
    }

    // MARK: - Ready Section

    /// "Ready to dictate", and the one sentence that says how.
    private var readySection: some View {
        VStack(spacing: 8) {
            Text("Ready to dictate")
                .font(.ouisprHeading)
                .foregroundStyle(Color.ouisprTextPrimary)
            Text("Tap the mic and speak.")
                .font(.ouisprBody)
                .foregroundStyle(Color.ouisprTextSecondary)
            // During the reverse trial, the one indicator it gets on this screen
            // (#593): discreet, never a nag.
            if let daysLeft = proStatus.trialBadgeDaysLeft {
                ProTrialBadge(daysLeft: daysLeft)
                    .padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
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

    // MARK: - Last Transcription Card

    /// Shows the most recent transcription result in a tappable glass card.
    /// Tap to copy to clipboard (same behavior as RecordingView result).
    private func transcriptionCard(result: String) -> some View {
        Button {
            UIPasteboard.general.string = result
            HapticFeedback.recordingStopped()
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showCopiedFeedback ? "Copied!" : "Last transcription")
                        .font(.ouisprCaption)
                        .foregroundColor(showCopiedFeedback ? .ouisprSuccess : .secondary)
                        .animation(.easeOut(duration: Motion.quick), value: showCopiedFeedback)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Text(result)
                    .font(.ouisprBody)
                    .foregroundStyle(Color.ouisprTextPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .ouisprGlass()
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
    }

    // MARK: - New Dictation Button

    /// The mic, centred, with the Smart Mode dial behind it (#489). No resting hint since
    /// 25 Nov 2026: Alex asked for the arrows around the mic to go.
    ///
    /// Everything Smart Mode draws here is an overlay or a background on the mic: the
    /// ring, the line under it. None of it owns layout, so the mic is
    /// exactly where #788 put it whatever the dial is doing, and the recording screen,
    /// which lines its own button up on this one, sees no difference.
    private var micRow: some View {
        newDictationButton
            // The ring behind the mic, so the mic draws over it.
            // Outside the button's accessibility modifiers on purpose: inside them, the
            // ring's symbols inherited the mic's identifier and read as more mics.
            .background {
                if let ringSession {
                    HomeSmartModeRing(session: ringSession)
                        // The segments spring out on their own (`HomeSmartModeRing`); this is
                        // the way back into the mic, on release or cancel.
                        .transition(reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .scale(scale: HomeSmartModeRingStyle.segmentHiddenScale)))
                }
            }
            .overlay(alignment: .top) {
                if let ringSession, HomeSmartModeRingStyle.showsReleaseHint {
                    HomeSmartModeRingHint(hint: ringSession.hint)
                        .fixedSize()
                        .offset(y: OuisprHalo.size(isPill: false).height + 12)
                }
            }
            .frame(maxWidth: .infinity)
    }

    /// The round mic that starts a dictation. Only shown when a model is ready.
    ///
    /// Since 25 Nov 2026 the ink mic (`InkMicButton`), the recording screen's own.
    ///
    /// WHY `AnimatedMicButton` at first (#788): the onboarding and the recording screen already
    /// draw their mic with it, so the home action is the same object the user taps on
    /// the next screen. Its status is pinned to `.idle`: as soon as a dictation starts,
    /// MainTabView covers this screen with the recording overlay, which carries the
    /// live states.
    ///
    /// The armed Smart Mode (#489) shows on it twice: the mode's glyph in the brand's
    /// deep blue as its face, and the keyboard pill's own corner badge. Both only when
    /// the next dictation will actually run it. Normal is a plain mic.
    ///
    /// WHY a button that starts dictation instead of a NavigationLink to TestDictationView:
    /// NavigationLink pushes TestDictationView inside the NavigationStack. Meanwhile,
    /// MainTabView shows a RecordingView overlay when coordinator.status != .idle.
    /// This creates TWO stacked RecordingViews. When the overlay dismisses (status → idle),
    /// the pushed TestDictationView is still there with its nav bar visible.
    /// A Button just starts dictation — the MainTabView overlay handles the full UI.
    private var newDictationButton: some View {
        // The ink mic, the recording screen's own (bench of 25 Nov 2026).
        InkMicButton(
            phase: .resting,
            badge: ringSession == nil ? smartModeMic.effectiveMode?.badge : nil,
            face: micFace,
            showsPressFeedback: ringSession == nil
        ) {
            // The release of a long press still arrives here as a tap when the finger
            // lifts on the mic. The dial being open, or having just closed, is what says
            // so, and it must not also start a recording: lifting on the mic is the
            // dial's cancel.
            guard !isRingBusy else { return }
            startDictation()
        }
        // The mic grows while the dial is open, around its own centre: a render scale,
        // so the layout, the anchor the recording screen lines up on (#788) and the
        // dial's geometry do not move.
        .scaleEffect(ringSession != nil && !reduceMotion ? HomeSmartModeRingStyle.openMicScale : 1)
        .animation(reduceMotion ? HomeSmartModeRingStyle.reducedMotionFade : HomeSmartModeRingStyle.micSpring,
                   value: ringSession != nil)
        // The dial's gesture: hold for the keyboard fan's 0.35 s, then slide. Simultaneous
        // rather than high-priority so a plain tap pays no delay, the fan's own reasoning
        // (`ToolbarView.micPill`). The drag is measured in the dashboard's space so the
        // finger keeps being tracked once it leaves the button.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0,
                                               coordinateSpace: .named(Self.dashboardSpace)))
                .updating($ringGestureActive) { value, active, _ in
                    if case .second(true, _) = value { active = true }
                }
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }
                    if ringSession == nil { openRing() }
                    if let drag { moveRing(to: drag.location) }
                }
                .onEnded { value in
                    guard case .second(true, let drag) = value else { return }
                    if let drag { moveRing(to: drag.location) }
                    releaseRing()
                },
            including: smartModeMic.isOffered ? .all : .none
        )
        // A touch the system cancelled, or a long press lifted before the drag began,
        // never reaches `onEnded`: the gesture state resetting is the one signal left.
        .onChange(of: ringGestureActive) { _, active in
            if !active, ringSession != nil { closeRing(cancelled: true) }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(Self.dashboardSpace))
        } action: { frame in
            micFrame = frame
        }
        // The visible label went with the rectangle; VoiceOver keeps it, and hears the
        // mode the dictation will run as the value (#397's missing half, on this mic).
        .accessibilityLabel("New dictation")
        .accessibilityValue(smartModeMic.isOffered
                            ? Text(HomeSmartModeCopy.spokenName(of: smartModeMic.effectiveMode))
                            : Text(verbatim: ""))
        // The dial without the gesture, which VoiceOver takes for itself: one action per
        // row that may be chosen. Choosing arms the mode and stops there — the
        // double-tap that follows is the dictation, and VoiceOver reads the new value
        // first, so the user hears what they picked before anything records.
        .accessibilityActions {
            if let choices = smartModeChoices {
                ForEach(choices.entries.filter(choices.canChoose)) { entry in
                    Button(accessibilityActionName(for: entry)) { chooseFromAccessibility(entry) }
                }
            }
        }
        .accessibilityIdentifier("home.newDictation")
        // The recording screen draws its own button at this height, so tapping here
        // shows no jump (#788).
        .reportsPrimaryMicAnchor()
    }

    /// The mic's face: the targeted row's while the dial is open, the armed mode's at
    /// rest, nil for the plain mic.
    private var micFace: AnimatedMicButton.MicFace? {
        if let ringSession {
            return HomeSmartModeCopy.micFace(for: ringSession.micEntry)
        }
        return smartModeMic.effectiveMode.flatMap { HomeSmartModeCopy.micFace(for: .mode($0)) }
    }

    /// A tap on the mic, or a dial released on a mode after arming it.
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

    // MARK: - Smart Mode Dial

    /// Whether the dial is open or closed so recently that its release is still being
    /// delivered to the mic's tap and the dashboard's swipe.
    private var isRingBusy: Bool {
        if ringSession != nil { return true }
        guard let ringClosedAt else { return false }
        return Date().timeIntervalSince(ringClosedAt) < 0.4
    }

    /// Re-read what the home mic shows from the App Group.
    private func refreshSmartMode() {
        smartModeMic = SmartModeHomeMic.current
        smartModeChoices = smartModeMic.isOffered ? SmartModeHomePicker.current() : nil
    }

    /// Open the dial when the long press completes.
    ///
    /// Resolved at open, as the keyboard fan is: armability cannot change between the
    /// press and the release, and reading it once keeps `SystemLanguageModel` off the
    /// per-frame path of the drag.
    private func openRing() {
        guard let picker = SmartModeHomePicker.current() else { return }
        // Sized now, from the screen it opens on: about three quarters of the width, no
        // taller than the room above the mic.
        let radii = SmartModeRingLayout.radii(
            width: dashboardWidth,
            heightAbove: micFrame.midY - HomeSmartModeRingStyle.topClearance
        )
        // A firmer impact than the selection ticks that follow, so the hand tells
        // "it opened" from "it moved".
        HapticFeedback.longPressRecognized()
        withAnimation(reduceMotion ? HomeSmartModeRingStyle.reducedMotionFade : HomeSmartModeRingStyle.micSpring) {
            ringSession = SmartModeRingSession(
                picker: picker, innerRadius: radii.inner, outerRadius: radii.outer
            )
        }
        PersistentLog.log(.diagnosticProbe(
            component: "HomeView", instanceID: "-", action: "smartModeRingOpened",
            details: "entries=\(picker.entries.count) armed=\(picker.armedIdentifier ?? "normal") "
                + "radii=\(Int(radii.inner))-\(Int(radii.outer))"
        ))
    }

    /// Feed the finger's position, in the dashboard's space, to the dial.
    private func moveRing(to location: CGPoint) {
        guard var session = ringSession else { return }
        let point = CGPoint(x: location.x - micFrame.midX, y: location.y - micFrame.midY)
        let cue = session.move(to: point)
        ringSession = session
        if cue == .tick { HapticFeedback.keyTapped() }
    }

    /// Lift the finger: arm and record, open the paywall, refuse, or nothing.
    private func releaseRing() {
        guard let session = ringSession else { return }
        let outcome = session.commit()
        closeRing(cancelled: false)
        switch outcome {
        case .cancel:
            break
        case .refused:
            HapticFeedback.actionRefused()
        case .openPaywall:
            showPaywall = true
        case .record:
            refreshSmartMode()
            startDictation()
        }
        PersistentLog.log(.diagnosticProbe(
            component: "HomeView", instanceID: "-", action: "smartModeRingReleased",
            details: "outcome=\(Self.logName(outcome)) source=home"
        ))
    }

    private func closeRing(cancelled: Bool) {
        ringClosedAt = Date()
        withAnimation(reduceMotion ? HomeSmartModeRingStyle.reducedMotionFade : HomeSmartModeRingStyle.micSpring) {
            ringSession = nil
        }
        if cancelled {
            PersistentLog.log(.diagnosticProbe(
                component: "HomeView", instanceID: "-", action: "smartModeRingReleased",
                details: "outcome=interrupted source=home"
            ))
        }
    }

    /// VoiceOver's action for `entry`: arm it (Normal disarms), or open the paywall.
    private func chooseFromAccessibility(_ entry: SmartModeFanEntry) {
        guard let picker = SmartModeHomePicker.current() else { return }
        switch picker.choose(entry) {
        case .openPaywall:
            showPaywall = true
        case .armed, .disarmed:
            refreshSmartMode()
        case .refused:
            HapticFeedback.actionRefused()
        }
        PersistentLog.log(.diagnosticProbe(
            component: "HomeView", instanceID: "-", action: "smartModeChosen",
            details: "row=\(entry.id) source=homeAccessibility"
        ))
    }

    private func accessibilityActionName(for entry: SmartModeFanEntry) -> String {
        if case .pro = entry { return String(localized: "Ouispr Pro") }
        return String(localized: "Use \(HomeSmartModeCopy.spokenName(of: entry.smartMode))",
                      comment: "VoiceOver action on the Home mic that arms this Smart Mode. The placeholder is the mode's name, or Normal.")
    }

    private static func logName(_ outcome: SmartModeRingRelease) -> String {
        switch outcome {
        case .cancel: return "cancel"
        case .refused: return "refused"
        case .openPaywall: return "paywall"
        case .record(let entry): return "record:\(entry.id)"
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
