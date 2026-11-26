// OuisprApp/Views/DriftingCardRow.swift
// A row of dictation cards drifting sideways without end, and what moves it.
import SwiftUI
import OuisprCore

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
    /// Where the card drawn empty for `openID` sits on screen, in global coordinates:
    /// Home lands a new card exactly there, however this row is placed.
    var onOpenCardFrame: ((CGRect) -> Void)?
    /// Whether the cards show a two-line excerpt (the history) rather than a short title
    /// (Home).
    var showsExcerpt = false

    static let edgeFade: CGFloat = 20

    @State private var engine = DriftEngine()
    /// The caller's latest callbacks, read by the cards when tapped or pressed: the strip
    /// of cards compares equal from one frame to the next without them.
    @State private var callbacks = RowCallbacks()
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
    fileprivate struct RowLayout: Equatable {
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
            let title = showsExcerpt
                ? DictationCloud.title(for: record.text, maxWords: DictationCloud.excerptWords)
                : DictationCloud.title(for: record.text)
            let width = CGFloat(showsExcerpt ? DictationCloud.cardWidth(forExcerpt: title)
                                             : DictationCloud.cardWidth(forTitle: title))
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
        // A plain store, not observed: a tap reads whatever the caller gave last.
        callbacks.onOpen = onOpen
        callbacks.menu = menu
        callbacks.onOpenCardFrame = onOpenCardFrame
        return GeometryReader { geo in
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
                withAnimation(DictationCloudCard.spring) { place(unit: unit) }
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
                // The cards drawn for a whole screen's width either side of where the row
                // is: the strip is the same from one frame to the next until the finger
                // takes the row a screen further, so its cards are not evaluated again.
                let step = Double(max(width, 1))
                let base = (x / step).rounded(.down) * step
                strip(layout, unit: unit, width: width, sweep: (base - step)...(base + step))
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

    private func strip(_ layout: RowLayout, unit: Double, width: CGFloat, sweep: ClosedRange<Double>) -> some View {
        CardStrip(records: records, layout: layout, copies: DriftCruise.copies(unit: unit, width: Double(width)),
                  unit: unit, width: width, sweep: sweep, openID: openID, callbacks: callbacks)
            .equatable()
    }

    // MARK: Panned

    @ViewBuilder
    private func pannedRow(_ layout: RowLayout, width: CGFloat) -> some View {
        let rowWidth = Double(layout.unit - DictationCloudCard.gap)
        let pan = DriftPan(rowWidth: rowWidth, width: Double(width), margin: Double(Self.edgeFade))
        let cards = CardStrip(records: records, layout: layout, copies: 1, unit: Double(layout.unit),
                              width: width, sweep: -Double.infinity...Double.infinity,
                              openID: openID, callbacks: callbacks)
            .equatable()
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
                    // Bounded: a row taken off screen mid-flick draws no frames, so its
                    // engine never settles, and the check must not poll forever.
                    var checks = 0
                    repeat {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard touchCount == touch, manual else { return }
                        checks += 1
                    } while !engine.isSettled(drifting: !still) && checks < 40
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

/// The callbacks a row's cards call, kept by the row so the cards always reach the
/// caller's latest ones.
@MainActor
private final class RowCallbacks {
    var onOpen: (TranscriptionRecord, CGRect) -> Void = { _, _ in }
    var menu: ((TranscriptionRecord) -> AnyView)?
    var onOpenCardFrame: ((CGRect) -> Void)?
}

/// Every copy of a row's cards that is on screen at some offset of `sweep`; only those are
/// drawn, a long period's row would otherwise hold hundreds of cards.
///
/// WHY Equatable: under the finger the row is drawn again on every frame, and a view
/// holding closures never compares equal, so every card's body ran 120 times a second.
/// Compared on what it draws, the strip is left alone while only its offset moves.
private struct CardStrip: View, Equatable {
    let records: [TranscriptionRecord]
    let layout: DriftingCardRow.RowLayout
    let copies: Int
    let unit: Double
    let width: CGFloat
    let sweep: ClosedRange<Double>
    let openID: UUID?
    let callbacks: RowCallbacks

    nonisolated static func == (lhs: CardStrip, rhs: CardStrip) -> Bool {
        lhs.records == rhs.records && lhs.layout == rhs.layout && lhs.copies == rhs.copies
            && lhs.unit == rhs.unit && lhs.width == rhs.width && lhs.sweep == rhs.sweep
            && lhs.openID == rhs.openID && lhs.callbacks === rhs.callbacks
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
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

    // MARK: Cards

    /// One card. Title and width come from the row's layout, worked out once per change
    /// of the records.
    private func card(_ record: TranscriptionRecord, title: String, width: CGFloat) -> some View {
        GeometryReader { proxy in
            Button {
                callbacks.onOpen(record, proxy.frame(in: .global))
            } label: {
                DictationCloudCard(record: record, title: title, width: width)
            }
            .buttonStyle(GlassPressStyle())
            .opacity(openID == record.id ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                if openID == record.id { callbacks.onOpenCardFrame?(frame) }
            }
            // The native preview with the whole dictation, sized to its text, instead of
            // the card lifted with one line over an empty area (audit of 26 Nov 2026, n°6).
            .contextMenu {
                if let menu = callbacks.menu {
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
