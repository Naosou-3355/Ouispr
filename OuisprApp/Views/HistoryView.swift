// OuisprApp/Views/HistoryView.swift
// The saved dictations as a drifting cloud of glass cards, sorted by period, reached from Home.
import SwiftUI
import OuisprCore

/// The transcription history (#70): every saved dictation as a glass card.
///
/// From Home, a cloud of glass cards drifting slowly sideways (« Fiche historique et
/// accueil V1 », Alex, 24 Nov 2026): four periods in a bar at the bottom, a search
/// button beside it, a card that lifts open when tapped. No mic: one dictates from Home.
/// The search shows its results as a list, with the free window's count of older
/// matches (Pro offer, 25 Nov 2026).
///
/// Pushed from the Ouispr Pro hub (#216) it stays the list it was, under the feature's
/// switch: that screen is about the feature, not about reading.
///
/// WHY it is presented as a sheet by `HomeView` rather than pushed or given a tab:
/// the issue asks for a vertical transition out of the home screen and a swipe-down
/// back to it, and a sheet is both of those natively — including the interactive,
/// interruptible drag that a hand-rolled transition would have to reimplement. The
/// tab bar stays at three entries, which the brief is explicit about.
///
/// The search results and the hub's version are a `List`: swipe-to-delete is the
/// interaction #70 names, and `List` is the only thing on iOS that gives it. In the
/// cloud, a long press on a card offers Copy and Delete instead.
struct HistoryView: View {

    @EnvironmentObject var history: TranscriptionHistoryStore
    @EnvironmentObject var proStatus: ProStatusManager
    @Environment(\.dismiss) private var dismiss

    /// The record whose full text is on screen, driving the push. Not a
    /// `NavigationLink` per row: the link would draw its own disclosure chevron
    /// outside the card and take the row's tap area away from the card itself.
    @State private var selection: TranscriptionRecord?

    /// Whether this screen is pushed onto someone else's stack, as the Ouispr Pro hub
    /// does (#216), rather than presented as the home screen's sheet.
    ///
    /// WHY the two shapes differ: the sheet owns its navigation, so it brings a stack
    /// and a close chevron. Pushed, a second stack inside the hub's would nest two
    /// navigation bars, and the back button already is the way out.
    var isPushed = false

    /// What the search field holds (#621). Empty shows every record.
    @State private var query = ""

    /// Whether the search field replaces the period bar.
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool

    /// The period the cloud shows. Nil until the screen picks the newest one with cards.
    @State private var period: DictationCloud.Period?

    /// The card lifted open, if any.
    @State private var openedCard: OpenedCardState?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Opens the Ouispr Pro window from the "older dictations" row, on its history.
    @State private var showsPaywall = false

    /// What the query finds: free, the last `HistoryAvailability.freeSearchDays`
    /// days, with a count of the older matches; with Pro, everything (Pro offer,
    /// 25 Nov 2026). An empty query lists the whole history for everyone.
    ///
    /// Recomputed on every body pass, a linear scan of an in-memory list; see
    /// `TranscriptionSearch`. The Pro status and the switch are touched first so the
    /// window widens the moment either moves: the gate reads the App Group.
    private var searchResult: TranscriptionSearch.Result {
        _ = proStatus.isProActive
        _ = switches.isOn(.history)
        return TranscriptionSearch.search(
            history.records,
            query: query,
            now: Date(),
            windowDays: HistoryAvailability.freeSearchDays,
            unlimited: HistoryAvailability.searchIsUnlimited
        )
    }

    /// The records the query finds, newest first, in a stable order: a letter typed
    /// narrows the list, it does not reshuffle it (audit of 26 Nov 2026, n°4).
    private var visibleRecords: [TranscriptionRecord] {
        searchResult.found.enumerated()
            .sorted { $0.element.createdAt != $1.element.createdAt
                ? $0.element.createdAt > $1.element.createdAt : $0.offset < $1.offset }
            .map(\.element)
    }

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .accessibilityLabel("Close")
                        }
                    }
            }
            // The grabber says the sheet is draggable, which is the same statement the
            // hint on the home screen makes about the swipe that opened it.
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        Group {
            if isPushed {
                pushedList
            } else if history.records.isEmpty {
                emptyState
            } else {
                cloud
            }
        }
        .background(OuisprMist(isPaused: selection != nil || showsPaywall))
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selection) { record in
            // A shared voice note opens on its Summary + Transcript screen (#620).
            if record.source == .sharedFile {
                VoiceNoteResultView(noteID: record.id)
            } else {
                TranscriptionDetailView(record: record)
            }
        }
        .paywallCover(isPresented: $showsPaywall, entry: .feature(.history))
        .overlay {
            if let openedCard {
                OpenedDictationCard(
                    record: openedCard.record,
                    origin: openedCard.origin,
                    onShowDetail: {
                        self.openedCard = nil
                        selection = openedCard.record
                    },
                    onClose: { self.openedCard = nil }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Cloud

    /// The cards of one period, drifting, over the period bar; or, while a query is
    /// typed, the search's results.
    private var cloud: some View {
        VStack(spacing: 0) {
            // While searching, the list: the latest dictations while the field is empty,
            // the matches once something is typed, never the period's empty state (n°4).
            if isSearching {
                recordList
            } else {
                cloudField
            }
            periodBar
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .onAppear {
            if period == nil { period = firstPeriodWithCards }
        }
        .onChange(of: history.records) { _, _ in
            if let period, records(in: period).isEmpty { self.period = firstPeriodWithCards }
        }
    }

    private var shownPeriod: DictationCloud.Period { period ?? firstPeriodWithCards }

    private var firstPeriodWithCards: DictationCloud.Period {
        periodsWithCards.first ?? .today
    }

    /// The periods that hold a card: an empty one is not offered (n°16).
    private var periodsWithCards: [DictationCloud.Period] {
        DictationCloud.Period.allCases.filter { !records(in: $0).isEmpty }
    }

    /// A period's cards, newest first, without a card that would have no words (n°5) and
    /// without a repeat of the one before it (n°9).
    private func records(in period: DictationCloud.Period) -> [TranscriptionRecord] {
        let now = Date()
        let inPeriod = history.records.filter {
            DictationCloud.Period.of($0.createdAt, now: now) == period
                && !DictationCloud.title(for: $0.text).isEmpty
        }
        return DictationCloud.droppingRepeats(inPeriod) { $0.text }
    }

    /// Up to four rows, the newest cards at their heads, neighbours drifting opposite
    /// ways. Rows past the screen's edge draw only the cards on screen (`DriftingCardRow`).
    private var cloudField: some View {
        let cards = records(in: shownPeriod)
        // Two cards a row, up to four rows: Today's two cards are two rows, not one
        // lost in the middle of the screen (n°5).
        let rowCount = DictationCloud.historyRowCount(cards: cards.count)
        let rows = DictationCloud.cloudRows(cards, perRow: (cards.count + rowCount - 1) / rowCount)
        return Group {
            if cards.isEmpty {
                Text("No dictations in this period")
                    .font(.ouisprBody)
                    .foregroundStyle(Color.ouisprTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: DictationCloudCard.gap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        DriftingCardRow(
                            records: row,
                            direction: index.isMultiple(of: 2) ? -1 : 1,
                            speedFactor: index.isMultiple(of: 2) ? 1 : 0.8,
                            isPaused: openedCard != nil || selection != nil || showsPaywall,
                            openID: openedCard?.record.id,
                            onOpen: { record, frame in
                                guard isAvailable else { return }
                                HapticFeedback.keyTapped()
                                openedCard = OpenedCardState(record: record, origin: frame)
                            },
                            menu: { record in AnyView(cardMenu(record)) },
                            showsExcerpt: true
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A new period's cards come in together, their titles word by word.
                .id(shownPeriod)
                .transition(.opacity)
            }
        }
    }

    /// Copy and Delete, on a long press: the cloud's counterpart of the list's swipe.
    @ViewBuilder
    private func cardMenu(_ record: TranscriptionRecord) -> some View {
        if isAvailable {
            Button {
                UIPasteboard.general.string = record.text
                HapticFeedback.recordingStopped()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                delete(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Period bar

    /// « Une seule matière »: one glass capsule of periods, 52 pt tall, and the search
    /// button in the same glass, 10 pt apart. A grey pill slides under the chosen period
    /// on a spring with a slight overshoot (320 ms); the text keeps one weight so nothing
    /// shifts. While searching, the capsule is the field.
    private var periodBar: some View {
        HStack(spacing: 10) {
            if isSearching {
                searchCapsule
            } else {
                periodCapsule
            }
            Button(action: toggleSearch) {
                // Two symbols crossfading, not one replaced: the replace effect drew a
                // lone dot in the glass mid-way (audit of 26 Nov 2026, n°11).
                ZStack {
                    Image(systemName: "magnifyingglass").opacity(isSearching ? 0 : 1)
                    Image(systemName: "xmark").opacity(isSearching ? 1 : 0)
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.ouisprTextPrimary)
                .frame(width: 52, height: 52)
                .ouisprGlass(in: Circle())
            }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel(isSearching ? Text("Close search") : Text("Search"))
            .accessibilityIdentifier("history.search")
        }
    }

    private var periodCapsule: some View {
        GlassSegmentedBar(
            items: periodsWithCards,
            selection: Binding(get: { shownPeriod }, set: { period = $0 }),
            title: { Text(periodName($0)) },
            identifier: { "history.period.\($0.rawValue)" }
        )
    }

    private var searchCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.ouisprTextSecondary)
            TextField("Search transcriptions", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
        }
        .font(.ouisprBody)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .ouisprGlass(in: Capsule())
        .transition(.opacity)
    }

    private func toggleSearch() {
        withAnimation(.easeOut(duration: Motion.quick)) {
            isSearching.toggle()
        }
        if isSearching {
            searchFocused = true
        } else {
            query = ""
            searchFocused = false
        }
    }

    private func periodName(_ period: DictationCloud.Period) -> LocalizedStringKey {
        switch period {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .week: return "This week"
        case .older: return "Older"
        }
    }

    /// The feature's switch, observed so the content dims and unlocks as it moves
    /// (#216). The same object the switch above writes and the hub row reads.
    @ObservedObject private var switches = ProFeatureSwitches.shared

    /// Whether the records are live: `FeatureGate.isAvailable`, the one predicate.
    private var isAvailable: Bool {
        _ = switches.isOn(.history)
        _ = proStatus.isProActive
        return HistoryAvailability.isEntitled
    }

    // MARK: - List

    /// The search's results, while a query is typed in the period bar's field.
    ///
    /// WHY the no-results state is an overlay on the empty `List` rather than a view
    /// swapped in for it: the list keeps its place while the results come and go.
    private var recordList: some View {
        List {
            recordRows
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if showsNoResults {
                noResultsState
            }
        }
    }

    /// The Ouispr Pro hub's version (#216): the feature's switch first, as in the hub's
    /// other feature screens, then "How it works" and its demo (#686), then the records,
    /// dimmed and locked while it is off.
    ///
    /// WHY the home screen's sheet has no switch: that sheet only opens while History
    /// is on (`HistoryAvailability.entryPoint`), it is the place for reading, and a
    /// switch there would remove, under the user's finger, the very swipe that opened
    /// it. Turning a Pro feature on or off happens in one place, the hub.
    ///
    /// Search (#621) works here too, under the same rule as the sheet (no field over
    /// an empty history) plus the hub's: no field while History is switched off, since
    /// the records under the switch are locked. The field hangs off the hub's own
    /// navigation bar; no second stack is nested for it.
    private var pushedList: some View {
        List {
            ProFeatureSwitchSection(feature: .history)

            // What the feature does, and its demo (#686).
            ProFeatureHowItWorksSection(feature: .history, isAvailable: isAvailable)

            if history.records.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                recordRows
            }
        }
        .scrollContentBackground(.hidden)
        .modifier(HistorySearchField(isEnabled: pushedSearchIsEnabled, query: $query))
        .overlay {
            if pushedSearchIsEnabled && showsNoResults {
                noResultsState
            }
        }
        // A query left in place when the switch goes off would keep the locked list
        // filtered by a field the user can no longer see.
        .onChange(of: pushedSearchIsEnabled) { _, enabled in
            if !enabled { query = "" }
        }
    }

    /// Nothing found at all. With older matches past the free window the list is not
    /// empty in truth, and the row that says so stays visible instead.
    private var showsNoResults: Bool {
        visibleRecords.isEmpty && searchResult.olderMatches == 0
    }

    /// Whether the pushed history offers its search field: records to search, and
    /// History switched on.
    private var pushedSearchIsEnabled: Bool {
        !history.records.isEmpty && isAvailable
    }

    private var recordRows: some View {
        Group {
            // Rows act on the record's id, never on its position, so swipe-to-delete
            // and the context menu work the same on a filtered list.
            ForEach(visibleRecords) { record in
                Button {
                    // Guarded as well as locked below: a switched-off history is
                    // shown, not opened (#216 decision 5).
                    guard isAvailable else { return }
                    selection = record
                } label: {
                    HistoryCard(record: record)
                }
                .buttonStyle(GlassPressStyle(pressedScale: 0.98))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                // No action at all while History is switched off (#216): the
                // `disabled` below stops taps, and an empty builder is what stops a
                // swipe or a long-press from offering Delete on a locked list.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if isAvailable {
                        Button(role: .destructive) {
                            delete(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        // Explicit, because the destructive role is not enough here:
                        // MainTabView tints the whole tab hierarchy `.ouisprAccent`,
                        // the sheet inherits that environment, and it wins over the
                        // role. Measured on the simulator — the delete action drew
                        // brand blue, which reads as an ordinary action.
                        .tint(.red)
                    }
                }
                .contextMenu {
                    // The long-press half of the issue's "long-press or swipe to
                    // delete", with the copy the detail screen also offers: a
                    // long-press that only ever destroys is a trap to open by accident.
                    if isAvailable {
                        Button {
                            UIPasteboard.general.string = record.text
                            HapticFeedback.recordingStopped()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) {
                            delete(record)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if searchResult.olderMatches > 0 && PremiumFlags.paywallVisible {
                olderMatchesRow(count: searchResult.olderMatches)
            }
        }
        .proFeatureContent(isAvailable: isAvailable)
    }

    /// Says how many older dictations match, under the free window's results, and
    /// opens the Pro window on its history.
    ///
    /// WHY a row and not a silent cut: a search that hides what it found reads as a
    /// broken search. Stating the count is what makes the 7-day limit an offer.
    private func olderMatchesRow(count: Int) -> some View {
        Button {
            showsPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ProFeature.history.icon)
                    .font(.title3)
                    .foregroundColor(.ouisprAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) older dictations match")
                        .font(.ouisprBody.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("Search your whole history with Ouispr Pro")
                        .font(.ouisprCaption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding()
            .ouisprGlass()
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.98))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func delete(_ record: TranscriptionRecord) {
        withAnimation {
            history.delete(id: record.id)
        }
        // A shared voice note deleted here leaves the keyboard too: a delete is the
        // one way besides time it does (#639).
        VoiceNoteProcessor.shared.withdrawKeyboardDeliveries([record.id], reason: "deletedInHistory")
        HapticFeedback.recordingStopped()
    }

    // MARK: - No results

    /// Shown when the query finds nothing. It repeats the query so a typo is visible
    /// without reading the field again.
    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.ouisprAccent.opacity(0.7))
            Text("No results for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .font(.ouisprSubheading)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    /// Shown before the first dictation is saved. It names the action that fills the
    /// screen rather than only stating that it is empty, because on a fresh install
    /// this is the first thing the swipe-up hint leads to.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 44))
                .foregroundColor(.ouisprAccent.opacity(0.7))
            Text("No transcriptions yet")
                .font(.ouisprSubheading)
            Text("Your dictations are saved here automatically. The last 200 are kept, on this device only.")
                .font(.ouisprCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

/// One saved dictation: two lines of the text, then the date, the language and how
/// long the recording was.
///
/// Not private: the onboarding's history scene (#680) shows this very card, so the
/// scene and the screen it stands for cannot drift apart.
struct HistoryCard: View {

    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.text)
                .font(.ouisprBody)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                // Marked as a shared file, not a dictation (#620 decision 7).
                if record.source == .sharedFile {
                    Image(systemName: ProFeature.voiceNotes.icon)
                        .accessibilityLabel(Text("Voice note"))
                }
                Text(record.shortDateLabel)
                Text("·")
                Text(record.languageBadge)
                Text("·")
                Text(record.durationLabel)
                Spacer()
            }
            .font(.ouisprCaption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .ouisprGlass()
    }
}

#Preview {
    HistoryView()
        .environmentObject(TranscriptionHistoryStore.shared)
        .environmentObject(ProStatusManager())
}

/// `.searchable`, applied only when the list has something the user may search.
///
/// WHY a modifier and not `.searchable` with an empty prompt: a search field is a
/// promise, and over a locked or empty list it is one the screen cannot keep (#621).
private struct HistorySearchField: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query, prompt: Text("Search transcriptions"))
        } else {
            content
        }
    }
}
