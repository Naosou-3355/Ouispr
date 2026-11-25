// OuisprApp/Views/DictationCards.swift
// The glass dictation cards of Home and the history: a drifting row of them, and the card lifted open.
import SwiftUI
import OuisprCore

// MARK: - Card

/// One dictation as a cloud card: its short title in a glass pill, nothing else.
///
/// « Fiche historique et accueil V1 » (Alex, 24 Nov 2026): real glass, a 2-3 word
/// title, 96 pt tall, 30 pt corners. The words come in one by one, from blurred to
/// sharp, the rule every dictated text follows.
struct DictationCloudCard: View {
    let record: TranscriptionRecord

    static let height: CGFloat = 96
    static let cornerRadius: CGFloat = 30
    static let gap: CGFloat = 8

    var title: String { DictationCloud.title(for: record.text) }
    var width: CGFloat { CGFloat(DictationCloud.cardWidth(forTitle: title)) }

    var body: some View {
        DictationTitleReveal(title: title, id: record.id)
            .padding(.horizontal, 18)
            .frame(width: width, height: Self.height)
            .ouisprGlass(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: record.text))
            .accessibilityHint(Text(record.shortDateLabel))
            .accessibilityIdentifier("history.card")
    }
}

/// A card's title, word by word: blurred 6 pt to sharp in 0.35 s, a word every 0.11 s
/// (`WordRevealPlan`). Two lines at the largest text sizes, then an ellipsis.
private struct DictationTitleReveal: View {
    let title: String

    let id: UUID

    /// Already shown sharp when this card's title came in before (`RevealedTitles`).
    @State private var shown: Bool

    init(title: String, id: UUID) {
        self.title = title
        self.id = id
        _shown = State(initialValue: RevealedTitles.seen.contains(id))
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let words = title.split(separator: " ").map(String.init)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text(verbatim: word)
                        .opacity(shown ? 1 : 0)
                        .blur(radius: shown || reduceMotion ? 0 : 6)
                        .animation(.easeOut(duration: WordRevealPlan.wordDuration)
                                    .delay(reduceMotion ? 0 : Double(index) * 0.11), value: shown)
                }
            }
            .lineLimit(1)
            Text(verbatim: title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: WordRevealPlan.wordDuration), value: shown)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(Color.ouisprTextPrimary)
        .onAppear {
            // Once per card and launch: a card drifting back into view, or drawn again by
            // its row, is not a new dictation.
            RevealedTitles.seen.insert(id)
            shown = true
        }
    }
}

/// The cards whose title has already come in word by word.
@MainActor
private enum RevealedTitles {
    static var seen = Set<UUID>()
}

// MARK: - Drifting row

/// A row of cards drifting sideways at 10 pt/s, without end: the cards are drawn several
/// times over and the row wraps by one period, which changes nothing on screen.
///
/// The drift stops under the finger, the row follows a drag and keeps a flick's momentum,
/// then the drift comes back after 1.5 s along a 0.13 s ramp. Stopped while `isPaused`
/// (a card open, a dictation, Reduce Motion), which also stops the frames.
struct DriftingCardRow: View {
    let records: [TranscriptionRecord]
    /// +1 drifts right, -1 left: two neighbouring rows go opposite ways.
    let direction: Double
    var speedFactor: Double = 1
    var isPaused = false
    /// The record whose card is open elsewhere, drawn empty here.
    var openID: UUID?
    let onOpen: (TranscriptionRecord, CGRect) -> Void
    /// The long-press menu, when the screen offers one (the history's Copy and Delete).
    var menu: ((TranscriptionRecord) -> AnyView)?

    @State private var engine = DriftEngine()
    /// Whether the finger is on the row, or its flick still runs: the frames then come at
    /// the display's rate, so the row follows the finger.
    @State private var isHandled = false
    /// The last touch, so a release does not end the full rate of a later touch.
    @State private var touchCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver cannot follow a card that moves under its cursor: the row stands still.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase

    /// Each card's width and where it starts in one period of the row.
    private struct RowLayout {
        var widths: [CGFloat] = []
        var starts: [CGFloat] = []
        /// One period: every card and its gap.
        var unit: CGFloat = 0
    }

    private var layout: RowLayout {
        var layout = RowLayout()
        for record in records {
            let width = CGFloat(DictationCloud.cardWidth(forTitle: DictationCloud.title(for: record.text)))
            layout.widths.append(width)
            layout.starts.append(layout.unit)
            layout.unit += width + DictationCloudCard.gap
        }
        return layout
    }

    var body: some View {
        GeometryReader { geo in
            let layout = layout
            let unit = max(layout.unit, 1)
            let copies = Int(((2 * unit + geo.size.width) / unit).rounded(.up)) + 1
            let still = isPaused || reduceMotion || voiceOver || scenePhase != .active
            // At rest the drift redraws 60 times a second, not at ProMotion's 120: at 10 pt/s
            // a frame moves a sixth of a point either way, and Home stays on screen for
            // minutes (Alex, 25 Nov 2026, after the Mac heated up under the simulators).
            TimelineView(.animation(minimumInterval: isHandled ? nil : 1.0 / 60,
                                    paused: still && !engine.isMoving && !isHandled)) { timeline in
                let x = CGFloat(engine.offset(at: timeline.date.timeIntervalSinceReferenceDate,
                                              unit: Double(unit), direction: direction,
                                              speedFactor: speedFactor, drifting: !still))
                // A row narrower than the screen does not loop, which would show its own
                // cards twice side by side: it sways in place, centred.
                let fits = unit - DictationCloudCard.gap <= geo.size.width
                let sway = fits ? swayOffset(rowWidth: unit - DictationCloudCard.gap, in: geo.size.width,
                                             at: timeline.date.timeIntervalSinceReferenceDate, still: still) : 0
                // Only the cards on screen are drawn: a long period's row would otherwise
                // hold hundreds of glass views, three times over.
                ZStack(alignment: .topLeading) {
                    ForEach(0..<(fits ? 1 : copies), id: \.self) { copy in
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            let left = fits ? sway + layout.starts[index]
                                            : x + CGFloat(copy) * unit + layout.starts[index]
                            if left + layout.widths[index] > 0 && left < geo.size.width {
                                card(record)
                                    .offset(x: left)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: DictationCloudCard.height, alignment: .topLeading)
            }
            // Not clipped: the row runs to the screen's edges, which clip it, and a clip
            // here cut the glass's own shadow into a visible band.
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
        }
        .frame(height: DictationCloudCard.height)
    }

    /// Where a short row sits: centred, drifting slowly to either side by at most 24 pt
    /// (one swing every 12 s, at most about the looping rows' 10 pt/s).
    private func swayOffset(rowWidth: CGFloat, in width: CGFloat, at time: Double, still: Bool) -> CGFloat {
        let centred = (width - rowWidth) / 2
        guard !still else { return centred }
        let amplitude = min(24, centred)
        return centred + amplitude * CGFloat(sin(time * 2 * .pi / 12) * direction)
    }

    private func card(_ record: TranscriptionRecord) -> some View {
        GeometryReader { proxy in
            Button {
                onOpen(record, proxy.frame(in: .global))
            } label: {
                DictationCloudCard(record: record)
            }
            .buttonStyle(GlassPressStyle())
            .opacity(openID == record.id ? 0 : 1)
            .contextMenu {
                if let menu { menu(record) }
            }
        }
        .frame(width: CGFloat(DictationCloud.cardWidth(forTitle: DictationCloud.title(for: record.text))),
               height: DictationCloudCard.height)
    }

    /// The finger holds the row (a zero-distance drag, alongside the cards' taps), drags it
    /// once it has moved 6 pt, and leaves it its velocity.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isHandled {
                    isHandled = true
                    touchCount += 1
                }
                engine.hold(translation: Double(value.translation.width))
            }
            .onEnded { value in
                engine.release(velocity: Double(value.velocity.width),
                               now: Date().timeIntervalSinceReferenceDate)
                // A flick dies down in about 2 s (`DriftTrack`'s decay); the full rate
                // holds until then.
                let touch = touchCount
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if touchCount == touch { isHandled = false }
                }
            }
    }
}

/// The row's moving state, read by its timeline on every frame.
///
/// WHY a class kept in `@State` and not `@State` values: the timeline reads and advances
/// it while drawing, and changing view state during a body pass is what SwiftUI forbids.
/// Nothing observes it; the timeline's own ticks are what redraw the row.
@MainActor
final class DriftEngine {
    private var track: DriftTrack?
    private var lastTime: Double?
    private var holding = false
    private var lastTranslation: Double = 0
    private var dragging = false
    private var resumeAt: Double = 0

    /// Whether a flick or a ramp is still running, which keeps the frames coming while
    /// the row is otherwise paused.
    var isMoving: Bool { (track?.fling ?? 0) != 0 || (track?.speed ?? 0) > 0.05 }

    func offset(at time: Double, unit: Double, direction: Double, speedFactor: Double, drifting: Bool) -> Double {
        if track?.unit != unit {
            // A first row starts just inside the screen's edge; a new period (a card came
            // or went) starts again from there.
            track = DriftTrack(unit: unit, direction: direction, speedFactor: speedFactor,
                               start: direction < 0 ? -unit + 14 : -unit - 60)
        }
        let dt = lastTime.map { min(0.05, max(0, time - $0)) } ?? 0
        lastTime = time
        let target = drifting && !holding && time >= resumeAt ? DictationCloud.driftSpeed : 0
        track?.step(dt, targetSpeed: target)
        return track?.x ?? 0
    }

    func hold(translation: Double) {
        holding = true
        if !dragging, abs(translation) > 6 { dragging = true; lastTranslation = translation }
        guard dragging else { return }
        track?.drag(by: translation - lastTranslation)
        lastTranslation = translation
    }

    func release(velocity: Double, now: Double) {
        if dragging { track?.release(velocity: velocity) }
        holding = false
        dragging = false
        lastTranslation = 0
        resumeAt = now + DictationCloud.resumeDelay
    }
}

// MARK: - Opened card

/// The card the user tapped, lifted out of its row and opened in place: same corners,
/// a uniform scale (no stretching), the cards' spring (0.32 s, damping 0.84). The full
/// text comes in word by word; copy and share are bare ink pictograms on 44 pt targets.
struct OpenedDictationCard: View {
    let record: TranscriptionRecord
    /// The card's frame in its row, in window coordinates, where it opens from.
    let origin: CGRect
    /// The history's way to the full screen of a record (a voice note's summary).
    var onShowDetail: (() -> Void)?
    let onClose: () -> Void

    @State private var open = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.84)

    var body: some View {
        GeometryReader { geo in
            let space = geo.frame(in: .global)
            let width = min(320, geo.size.width - 54)
            ZStack {
                // Tapping beside the card closes it.
                Color.black.opacity(open ? 0.06 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)

                content
                    .frame(width: width)
                    .background(
                        RoundedRectangle(cornerRadius: DictationCloudCard.cornerRadius, style: .continuous)
                            .fill(Color.ouisprSurface)
                            .shadow(color: .black.opacity(0.18), radius: 22, y: 12)
                    )
                    .scaleEffect(open || reduceMotion ? 1 : origin.width / width)
                    .offset(open || reduceMotion ? .zero : CGSize(width: origin.midX - space.midX,
                                                                  height: origin.midY - space.midY))
                    .opacity(open ? 1 : 0)
                    .accessibilityAddTraits(.isModal)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: Motion.standard) : Self.spring) { open = true }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: DictationCloud.title(for: record.text))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ouisprTextPrimary)
                Spacer(minLength: 8)
                Text(verbatim: copied ? String(localized: "Copied!") : record.shortDateLabel)
                    .font(.ouisprCaption)
                    .foregroundStyle(copied ? Color.ouisprSuccess : Color.ouisprTextSecondary)
                    .monospacedDigit()
            }
            ScrollView {
                RevealingText(record.text, font: .system(size: 15), wordSpacing: 4)
                    .foregroundStyle(Color.ouisprTextPrimary)
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                if let onShowDetail {
                    pictogram("arrow.up.left.and.arrow.down.right", label: "Open", action: onShowDetail)
                }
                Spacer()
                pictogram("doc.on.doc", label: "Copy", action: copy)
                ShareLink(item: record.text) {
                    pictogramGlyph("square.and.arrow.up")
                }
                .buttonStyle(GlassPressStyle())
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, -10)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func pictogram(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { pictogramGlyph(symbol) }
            .buttonStyle(GlassPressStyle())
            .accessibilityLabel(label)
    }

    private func pictogramGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.ouisprInk.opacity(0.5))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func copy() {
        UIPasteboard.general.string = record.text
        HapticFeedback.recordingStopped()
        withAnimation(.easeOut(duration: Motion.quick)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: Motion.quick)) { copied = false }
        }
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: Motion.standard) : Self.spring) {
            open = false
        } completion: {
            onClose()
        }
    }
}

/// A card open over a screen, and where it opened from.
struct OpenedCardState: Equatable {
    let record: TranscriptionRecord
    let origin: CGRect
}

// MARK: - Date

extension TranscriptionRecord {
    /// Today reads as a time, this year as a day and month, anything older carries the
    /// year. Formatted by Foundation rather than by a string in the catalogue: the order
    /// of the parts and the month's abbreviation are the user's locale's business.
    var shortDateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            return createdAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(createdAt, equalTo: Date(), toGranularity: .year) {
            return createdAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return createdAt.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
