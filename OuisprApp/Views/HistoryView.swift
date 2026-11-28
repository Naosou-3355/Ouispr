// OuisprApp/Views/HistoryView.swift
// The saved dictations as a native list, sorted by period, reached from Home.
import SwiftUI
import OuisprCore

/// The transcription history (#70): every saved dictation as a flat row, under the
/// period it was dictated in.
///
/// « Banc Ouispr épuré » (Alex, 27 Nov 2026): a large native title, sections Aujourd'hui,
/// Hier, Cette semaine, Plus ancien, the rows Home shows (`DictationRow`), and the
/// system's search field. It replaces the drifting cloud and its period bar: a list
/// reads top to bottom and is searched, a cloud had to be watched.
///
/// WHY the search is the system's `.searchable`: on iOS 26 the iPhone puts it at the
/// bottom of the screen, in thumb reach, which is what Alex asked for; on iOS 17 to 18 it
/// sits under the title, where those versions put every search field.
///
/// Pushed from the Ouispr Pro hub (#216) it carries the feature's switch first: that
/// screen is about the feature, not about reading.
///
/// WHY it is presented as a sheet by `HomeView` rather than pushed or given a tab:
/// the issue asks for a vertical transition out of the home screen and a swipe-down
/// back to it, and a sheet is both of those natively — including the interactive,
/// interruptible drag that a hand-rolled transition would have to reimplement.
///
/// A `List`: swipe-to-delete is the interaction #70 names, and `List` is the only thing
/// on iOS that gives it. A long press offers Copy and Delete.
struct HistoryView: View {

    @EnvironmentObject var history: TranscriptionHistoryStore
    @EnvironmentObject var proStatus: ProStatusManager
    @Environment(\.dismiss) private var dismiss

    /// The record whose full text is on screen, driving the push. Not a
    /// `NavigationLink` per row: the link would draw its own disclosure chevron.
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

    /// The rows' minimum height, grown with the text size as `DictationRow`'s is.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 72

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
    /// narrows the list, it does not reshuffle it (audit of 26 Nov 2026, n°4). Without
    /// the records that have no words and the repeats that follow each other, as on Home.
    private var visibleRecords: [TranscriptionRecord] {
        let sorted = searchResult.found.enumerated()
            .sorted { $0.element.createdAt != $1.element.createdAt
                ? $0.element.createdAt > $1.element.createdAt : $0.offset < $1.offset }
            .map(\.element)
        return DictationList.shown(sorted) { $0.text }
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
            // swipe up on the home screen makes about the gesture that opened it.
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        Group {
            if isPushed {
                pushedList
            } else if !history.records.contains(where: { DictationList.hasWords($0.text) }) {
                // No record with words: every row would be left out (`DictationList`).
                emptyState
            } else {
                sheetList
            }
        }
        .background(OuisprBackdrop())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
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

    // MARK: - Sheet list

    /// Home's sheet: the records by period, searched from the system's field.
    ///
    /// WHY the no-results state is an overlay on the empty `List` rather than a view
    /// swapped in for it: the list keeps its place while the results come and go.
    private var sheetList: some View {
        List {
            recordRows
        }
        .listStyle(.insetGrouped)
        // Home's row height, 72 pt at the default text size (`DictationRow`).
        .environment(\.defaultMinListRowHeight, rowHeight)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .modifier(HistorySearchField(isEnabled: searchIsEnabled, query: $query))
        .overlay {
            if showsNoResults {
                noResultsState
            }
        }
    }

    private func periodName(_ period: DictationList.Period) -> LocalizedStringKey {
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
        .modifier(HistorySearchField(isEnabled: searchIsEnabled, query: $query))
        .overlay {
            if searchIsEnabled && showsNoResults {
                noResultsState
            }
        }
        // A query left in place when the switch goes off would keep the locked list
        // filtered by a field the user can no longer see.
        .onChange(of: searchIsEnabled) { _, enabled in
            if !enabled { query = "" }
        }
    }

    /// Nothing found at all. With older matches past the free window the list is not
    /// empty in truth, and the row that says so stays visible instead.
    private var showsNoResults: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && visibleRecords.isEmpty && searchResult.olderMatches == 0
    }

    /// Whether the history offers its search field: records to search, and History
    /// switched on.
    private var searchIsEnabled: Bool {
        !history.records.isEmpty && isAvailable
    }

    /// The records under their periods, newest first, then the row that counts the
    /// older matches.
    private var recordRows: some View {
        Group {
            ForEach(DictationList.sections(visibleRecords, now: Date()) { $0.createdAt }, id: \.period) { section in
                Section {
                    // Rows act on the record's id, never on its position, so
                    // swipe-to-delete and the context menu work the same on a filtered list.
                    ForEach(section.items) { record in
                        row(record)
                    }
                } header: {
                    Text(periodName(section.period))
                }
            }

            if searchResult.olderMatches > 0 && PremiumFlags.paywallVisible {
                Section {
                    olderMatchesRow(count: searchResult.olderMatches)
                }
            }
        }
        .proFeatureContent(isAvailable: isAvailable)
    }

    private func row(_ record: TranscriptionRecord) -> some View {
        Button {
            // Guarded as well as locked below: a switched-off history is shown, not
            // opened (#216 decision 5).
            guard isAvailable else { return }
            selection = record
        } label: {
            DictationRow(record: record, pads: false)
        }
        // Flat (contrôle V1.1): the list's own surface, no glass on a row.
        .listRowBackground(Color.ouisprSurface)
        // No action at all while History is switched off (#216): the `disabled` that
        // `proFeatureContent` sets stops taps, and an empty builder is what stops a
        // swipe or a long-press from offering Delete on a locked list.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isAvailable {
                Button(role: .destructive) {
                    delete(record)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                // Explicit, because the destructive role is not enough here:
                // MainTabView tints the whole tab hierarchy `.ouisprAccent`, the sheet
                // inherits that environment, and it wins over the role. Measured on the
                // simulator — the delete action drew brand blue.
                .tint(.red)
            }
        }
        .contextMenu {
            // The long-press half of the issue's "long-press or swipe to delete", with
            // the copy the detail screen also offers: a long-press that only ever
            // destroys is a trap to open by accident.
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
                    .foregroundColor(.ouisprAccentText)
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
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.ouisprSurface)
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
                .foregroundColor(.ouisprAccentText.opacity(0.7))
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
                .foregroundColor(.ouisprAccentText.opacity(0.7))
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
