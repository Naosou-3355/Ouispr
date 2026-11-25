// OuisprApp/Views/HistoryView.swift
// The saved dictations, newest first, reached by swiping up from the home screen.
import SwiftUI
import OuisprCore

/// The transcription history (#70): every saved dictation as a glass card.
///
/// WHY it is presented as a sheet by `HomeView` rather than pushed or given a tab:
/// the issue asks for a vertical transition out of the home screen and a swipe-down
/// back to it, and a sheet is both of those natively — including the interactive,
/// interruptible drag that a hand-rolled transition would have to reimplement. The
/// tab bar stays at three entries, which the brief is explicit about.
///
/// WHY a `List` and not a `ScrollView` of cards: swipe-to-delete is the interaction
/// the issue names, and `List` is the only thing on iOS that gives it — with the
/// right hit area, the right rubber-banding and the right row-removal animation. The
/// glass look survives it: clear row backgrounds, no separators, no list background.
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

    /// The records the query finds, newest first.
    private var visibleRecords: [TranscriptionRecord] {
        searchResult.found
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
                recordList
            }
        }
        .background(Color.ouisprBackground.ignoresSafeArea())
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

    /// WHY `.searchable` sits on the list and not on the whole screen: the field has
    /// nothing to search on the locked and empty states, and a search bar above
    /// "No transcriptions yet" would promise something the screen cannot do.
    ///
    /// WHY the no-results state is an overlay on the empty `List` rather than a
    /// view swapped in for it: swapping would tear down the view that owns the
    /// search field, and the field would lose focus on the keystroke that empties
    /// the results.
    private var recordList: some View {
        List {
            recordRows
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: Text("Search transcriptions"))
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
            Text("No results")
                .font(.ouisprSubheading)
            Text("No transcription contains “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                .font(.ouisprCaption)
                .foregroundColor(.secondary)
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
                Text(dateLabel)
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

    /// Today reads as a time, this year as a day and month, anything older carries
    /// the year. Formatted by Foundation rather than by a string in the catalogue:
    /// the order of the parts and the month's abbreviation are the user's locale's
    /// business, not a translation.
    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.createdAt) {
            return record.createdAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(record.createdAt, equalTo: Date(), toGranularity: .year) {
            return record.createdAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return record.createdAt.formatted(.dateTime.day().month(.abbreviated).year())
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
