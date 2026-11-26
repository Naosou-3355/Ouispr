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
    let title: String
    let width: CGFloat

    static let height: CGFloat = 96
    static let cornerRadius: CGFloat = 30
    static let gap: CGFloat = 8

    /// The drifting cards drawn in pre-rendered glass instead of live glass: an internal
    /// switch for the jank audit of 26 Nov 2026 (launch argument `-OuisprFauxGlass YES`),
    /// off by default until the device says which one Alex keeps.
    static var usesFauxGlass: Bool { UserDefaults.standard.bool(forKey: "OuisprFauxGlass") }

    /// Title and width are worked out once by the caller that has them (the drifting
    /// row's layout); a card on its own works them out here.
    init(record: TranscriptionRecord, title: String? = nil, width: CGFloat? = nil) {
        self.record = record
        let title = title ?? DictationCloud.title(for: record.text)
        self.title = title
        self.width = width ?? CGFloat(DictationCloud.cardWidth(forTitle: title))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        DictationTitleReveal(title: title, id: record.id)
            .padding(.horizontal, 18)
            .frame(width: width, height: Self.height)
            .modifier(CardGlass(shape: shape, faux: Self.usesFauxGlass))
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: record.text))
            .accessibilityHint(Text(record.shortDateLabel))
            .accessibilityIdentifier("history.card")
    }
}

/// The card's material: Liquid Glass, or its pre-rendered stand-in.
///
/// WHY a stand-in exists: live glass samples and blurs what is behind it on every frame
/// the card moves, and a drifting row moves every frame. The stand-in is a translucent
/// fill and a hairline highlight (a `drawingGroup` cost the render server more, measured): moving it
/// costs a translation, nothing is sampled.
private struct CardGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let faux: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if faux {
            let dark = colorScheme == .dark
            content
                .background {
                    shape
                        .fill(Color.white.opacity(dark ? 0.09 : 0.55))
                        .overlay {
                            shape.strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(dark ? 0.28 : 0.9), Color.white.opacity(dark ? 0.06 : 0.25)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                        }
                }
        } else {
            content.ouisprGlass(in: shape)
        }
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
                    // From a faint blur, never from nothing: a card is never an empty chip.
                    Text(verbatim: word)
                        .opacity(shown ? 1 : 0.25)
                        .blur(radius: shown || reduceMotion ? 0 : 6)
                        .animation(.easeOut(duration: WordRevealPlan.wordDuration)
                                    .delay(reduceMotion ? 0 : Double(index) * 0.11), value: shown)
                }
            }
            .lineLimit(1)
            Text(verbatim: title)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .opacity(shown ? 1 : 0.25)
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
enum RevealedTitles {
    fileprivate static var seen = Set<UUID>()

    /// A card whose words must show at once, such as the one flying in from the character.
    static func markSeen(_ id: UUID) { seen.insert(id) }
}

// MARK: - Drifting row

/// A row of cards drifting sideways at 10 pt/s, without end: the cards are drawn several
/// times over and the row wraps by one period, which changes nothing on screen.
///
/// Three ways of moving (jank audit, 26 Nov 2026):
/// - cruising: one linear move by a period, repeated forever, run by the animation system;
///   the row's body is not evaluated again until something changes;
/// - under the finger: a timeline at the display's rate follows the drag, keeps a flick's
///   momentum, and gives the row back to the cruise once it drifts at full speed again;
/// - panned: a row too short to loop without showing a card twice (n°9) swings slowly
///   from side to side instead.
/// Stopped while `isPaused` (a card open, a sheet, a dictation), under Reduce Motion and
/// VoiceOver, and outside the active scene.
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

    static let edgeFade: CGFloat = 20

    @State private var engine = DriftEngine()
    /// The finger holds the row, or its flick still runs.
    @State private var manual = false
    /// The running cruise, nil while the row stands still or is under the finger.
    @State private var cruise: DriftCruise?
    /// Where a still row stands.
    @State private var restX: Double?
    /// The period the positions above belong to: a card that comes or goes starts again.
    @State private var placedUnit: Double = 0
    /// The last touch, so a release does not end a later touch's manual mode.
    @State private var touchCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver cannot follow a card that moves under its cursor: the row stands still.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase

    /// Each card's width and where it starts in one period of the row.
    private struct RowLayout {
        var titles: [String] = []
        var widths: [CGFloat] = []
        var starts: [CGFloat] = []
        /// One period: every card and its gap.
        var unit: CGFloat = 0
        var widest: CGFloat = 0
    }

    private var layout: RowLayout {
        var layout = RowLayout()
        for record in records {
            let title = DictationCloud.title(for: record.text)
            let width = CGFloat(DictationCloud.cardWidth(forTitle: title))
            layout.titles.append(title)
            layout.widths.append(width)
            layout.starts.append(layout.unit)
            layout.unit += width + DictationCloudCard.gap
            layout.widest = max(layout.widest, width)
        }
        return layout
    }

    private var still: Bool { isPaused || reduceMotion || voiceOver || scenePhase != .active }

    private static var now: Double { Date().timeIntervalSinceReferenceDate }

    var body: some View {
        GeometryReader { geo in
            let layout = layout
            let width = geo.size.width
            let unit = Double(max(layout.unit, 1))
            let loops = DriftCruise.loops(unit: unit, widestCard: Double(layout.widest), width: Double(width))
            Group {
                if loops {
                    loopingRow(layout, unit: unit, width: width)
                } else {
                    pannedRow(layout, width: width)
                }
            }
            .frame(width: width, height: DictationCloudCard.height, alignment: .topLeading)
            // The cards fade out over the last 20 pt rather than being cut by the screen's
            // edge (n°10). Taller than the row: a mask its height would cut the glass's
            // shadow into a band.
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: Self.edgeFade / max(width, 1)),
                    .init(color: .black, location: 1 - Self.edgeFade / max(width, 1)),
                    .init(color: .clear, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
                .frame(height: DictationCloudCard.height + 80)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(unit: unit), including: loops ? .all : .subviews)
            .onAppear { place(unit: unit) }
            // A card that comes or goes moves the others along rather than making them jump.
            .onChange(of: unit) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { place(unit: unit) }
            }
            .onChange(of: still) { place(unit: unit) }
        }
        .frame(height: DictationCloudCard.height)
    }

    // MARK: Looping

    @ViewBuilder
    private func loopingRow(_ layout: RowLayout, unit: Double, width: CGFloat) -> some View {
        if manual {
            TimelineView(.animation) { timeline in
                let x = engine.offset(at: timeline.date.timeIntervalSinceReferenceDate, drifting: !still)
                strip(layout, unit: unit, width: width, sweep: x...x)
                    .offset(x: CGFloat(x))
            }
        } else if let cruise {
            let sweep = min(cruise.start, cruise.end)...max(cruise.start, cruise.end)
            AnimatedOffset(from: cruise.start, to: cruise.end,
                           animation: .linear(duration: cruise.period).repeatForever(autoreverses: false)) {
                strip(layout, unit: unit, width: width, sweep: sweep)
            }
            .id(cruise)
        } else {
            let x = restX ?? Self.initialX(unit: unit, direction: direction)
            strip(layout, unit: unit, width: width, sweep: x...x)
                .offset(x: CGFloat(x))
        }
    }

    /// Every copy of the cards that is on screen at some offset of `sweep`; only those are
    /// drawn, a long period's row would otherwise hold hundreds of glass views.
    private func strip(_ layout: RowLayout, unit: Double, width: CGFloat, sweep: ClosedRange<Double>) -> some View {
        let copies = DriftCruise.copies(unit: unit, width: Double(width))
        return ZStack(alignment: .topLeading) {
            ForEach(0..<copies, id: \.self) { copy in
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    let left = Double(copy) * unit + Double(layout.starts[index])
                    if left + sweep.upperBound + Double(layout.widths[index]) > 0
                        && left + sweep.lowerBound < Double(width) {
                        card(record, title: layout.titles[index], width: layout.widths[index])
                            .offset(x: CGFloat(left))
                    }
                }
            }
        }
        .frame(width: width, height: DictationCloudCard.height, alignment: .topLeading)
    }

    // MARK: Panned

    @ViewBuilder
    private func pannedRow(_ layout: RowLayout, width: CGFloat) -> some View {
        let rowWidth = Double(layout.unit - DictationCloudCard.gap)
        let pan = DriftPan(rowWidth: rowWidth, width: Double(width), margin: Double(Self.edgeFade))
        let cards = ZStack(alignment: .topLeading) {
            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                card(record, title: layout.titles[index], width: layout.widths[index])
                    .offset(x: layout.starts[index])
            }
        }
        .frame(width: width, height: DictationCloudCard.height, alignment: .topLeading)
        if still {
            cards.offset(x: CGFloat(rowWidth <= Double(width) ? (Double(width) - rowWidth) / 2 : pan.to))
        } else {
            let (from, to) = direction >= 0 ? (pan.from, pan.to) : (pan.to, pan.from)
            AnimatedOffset(from: from, to: to,
                           animation: .easeInOut(duration: pan.duration).repeatForever(autoreverses: true)) {
                cards
            }
            .id(pan)
        }
    }

    // MARK: Cards

    /// One card. Title and width come from the row's layout, worked out once per change
    /// of the records.
    private func card(_ record: TranscriptionRecord, title: String, width: CGFloat) -> some View {
        GeometryReader { proxy in
            Button {
                onOpen(record, proxy.frame(in: .global))
            } label: {
                DictationCloudCard(record: record, title: title, width: width)
            }
            .buttonStyle(GlassPressStyle())
            .opacity(openID == record.id ? 0 : 1)
            // The native preview with the whole dictation, sized to its text, instead of
            // the card lifted with one line over an empty area (audit of 26 Nov 2026, n°6).
            .contextMenu {
                if let menu {
                    menu(record)
                } else {
                    Button {
                        UIPasteboard.general.string = record.text
                        HapticFeedback.keyTapped()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: record.text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            } preview: {
                DictationPreview(record: record)
            }
        }
        .frame(width: width, height: DictationCloudCard.height)
    }

    // MARK: Moving between modes

    /// A first row starts just inside the screen's edge.
    private static func initialX(unit: Double, direction: Double) -> Double {
        DriftTrack(unit: unit, direction: direction, start: direction < 0 ? -unit + 14 : -unit - 60).x
    }

    /// Where the row is now, whichever way it moves.
    private func currentX(unit: Double) -> Double {
        guard placedUnit == unit else { return Self.initialX(unit: unit, direction: direction) }
        if let cruise { return cruise.x(at: Self.now) }
        return restX ?? Self.initialX(unit: unit, direction: direction)
    }

    /// Cruise or stand still from where the row is, unless the finger has it.
    private func place(unit: Double) {
        guard !manual else { return }
        let x = currentX(unit: unit)
        placedUnit = unit
        if still {
            cruise = nil
            restX = x
        } else {
            restX = nil
            cruise = DriftCruise(from: x, at: Self.now, unit: unit, direction: direction, speedFactor: speedFactor)
        }
    }

    /// The finger holds the row (a zero-distance drag, alongside the cards' taps), drags it
    /// once it has moved 6 pt, and leaves it its velocity.
    private func dragGesture(unit: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !manual {
                    engine.take(x: currentX(unit: unit), unit: unit, direction: direction,
                                speedFactor: speedFactor, speed: still ? 0 : DictationCloud.driftSpeed)
                    cruise = nil
                    manual = true
                }
                if value.translation == .zero { touchCount += 1 }
                engine.hold(translation: Double(value.translation.width))
            }
            .onEnded { value in
                engine.release(velocity: Double(value.velocity.width), now: Self.now)
                let touch = touchCount
                Task { @MainActor in
                    // Back to the cruise once the flick has died down and the drift is at
                    // full speed again (about 2 s), not before: the cruise has one speed.
                    repeat {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard touchCount == touch, manual else { return }
                    } while !engine.isSettled(drifting: !still)
                    let x = engine.x ?? currentX(unit: unit)
                    manual = false
                    restX = x
                    placedUnit = unit
                    cruise = nil
                    place(unit: unit)
                }
            }
    }
}

/// A card's long-press preview: the whole dictation and its date, as wide as the text
/// needs up to 320 pt.
private struct DictationPreview: View {
    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: record.shortDateLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.ouisprTextSecondary)
            Text(verbatim: record.text)
                .font(.system(size: 16))
                .foregroundStyle(Color.ouisprTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .background(Color.ouisprSurface)
    }
}

/// A view moved from one offset to another by a repeating animation, started when it
/// appears. Its parent gives it a new identity to start another one.
private struct AnimatedOffset<Content: View>: View {
    let to: Double
    let animation: Animation
    let content: Content
    @State private var x: Double

    init(from: Double, to: Double, animation: Animation, @ViewBuilder content: () -> Content) {
        self.to = to
        self.animation = animation
        self.content = content()
        _x = State(initialValue: from)
    }

    var body: some View {
        content
            .offset(x: CGFloat(x))
            .onAppear {
                withAnimation(animation) { x = to }
            }
    }
}

/// The row's state under the finger, read by its timeline on every frame.
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

    var x: Double? { track?.x }

    /// Take the row over where it stands, at the speed it drifts.
    func take(x: Double, unit: Double, direction: Double, speedFactor: Double, speed: Double) {
        track = DriftTrack(unit: unit, direction: direction, speedFactor: speedFactor, start: x, speed: speed)
        lastTime = nil
        resumeAt = 0
    }

    /// No flick left, and the drift back at its full speed (or at rest when it must not drift).
    func isSettled(drifting: Bool) -> Bool {
        guard !holding, let track else { return !holding }
        guard track.fling == 0 else { return false }
        return drifting ? track.speed > DictationCloud.driftSpeed * 0.97 : track.speed < 0.05
    }

    func offset(at time: Double, drifting: Bool) -> Double {
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
