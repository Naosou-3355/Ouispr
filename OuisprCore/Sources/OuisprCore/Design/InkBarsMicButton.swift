#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/InkBarsMicButton.swift
// The keyboard bar's mic: the logo's three bars in ink, nothing around them.
import SwiftUI

/// The mic at the end of the keyboard's bar (lot 1.4, Alex on the keyboard bench of
/// 27 Nov 2026: « Pas de bouton, je veux juste l'icône pleine »). The logo's three bars,
/// filled with the app's ink: no disc, no capsule, no glass, no halo. The armed mode's
/// badge stays on its corner.
///
/// WHY HERE AND NOT IN THE KEYBOARD TARGET: it reuses `InkMicBars` and the badge drawing,
/// both in OuisprCore, and the keyboard target lists its files one by one in the project.
public struct InkBarsMicButton: View {
    public let status: DictationStatus
    /// The armed Smart Mode's mark, or nil when nothing is armed (#79).
    public let badge: SmartModeBadge?
    /// Goes up by one each time a dictation's text is written (lot 1.6). A new value plays
    /// the laughing eyes once: ✓, then ^ ^ for about 0.6 s, then the bars again.
    public let celebrationID: Int
    public let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glyph on screen: the bars, or a moment of the celebration.
    @State private var strokes = InkMicGlyph.bars.strokes
    @State private var glyphOpacity: Double = 1

    /// The last celebration played in this process. WHY STATIC: iOS keeps several
    /// keyboard controllers alive and rebuilds the bar when the listening screen leaves,
    /// so a per-view memory would replay the smile on every rebuild. One per process
    /// plays it once.
    @MainActor private static var lastCelebratedID = 0

    public init(
        status: DictationStatus,
        badge: SmartModeBadge? = nil,
        celebrationID: Int = 0,
        onTap: @escaping () -> Void
    ) {
        self.status = status
        self.badge = badge
        self.celebrationID = celebrationID
        self.onTap = onTap
    }

    /// The bench's spring (28 Nov 2026): lively, about 0.35 s, a slight overshoot.
    public static let morphSpring = Animation.spring(response: 0.35, dampingFraction: 0.72)

    /// The bars' box: the tallest bar about 23 pt, the size of the bar's other glyphs.
    private static let glyphSide: CGFloat = 26
    /// Apple's minimum touch target (HIG, Accessibility), wider to sit where the 56 pt
    /// pill sat, so the bar's layout does not move.
    private static let targetSize = CGSize(width: 56, height: 44)

    /// Only idle, ready and failed start a dictation.
    private var isTappable: Bool {
        status == .idle || status == .ready || status == .failed
    }

    public var body: some View {
        Button {
            // `.disabled` should prevent this; logged if it is ever reached.
            guard isTappable else {
                PersistentLog.log(.rapidTapRejected)
                return
            }
            onTap()
        } label: {
            ZStack {
                // The bars as four strokes (lot 1.6), so they can spring into ^ ^ and
                // back. At rest they are exactly `InkMicBars`.
                InkStrokesShape(strokes)
                    .fill(Color.ouisprInk)
                    .frame(width: Self.glyphSide, height: Self.glyphSide)
                    .opacity(glyphOpacity)
                armedBadge
            }
            .frame(width: Self.targetSize.width, height: Self.targetSize.height)
            // WHY A NEAR-INVISIBLE FILL: in a keyboard extension a touch on fully
            // transparent pixels is not delivered to the view at all, `contentShape` or
            // not (measured by the smoke test on 27 Nov 2026: a tap between two bars never
            // reached the mic). The old pill was opaque all over; the bare bars are not.
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.88, pressedOpacity: 0.7))
        .disabled(!isTappable)
        .accessibilityLabel(Text("Dictate", bundle: .main, comment: "VoiceOver name of the keyboard's mic (lot 1.4)."))
        .onAppear { celebrateIfNew() }
        .onChange(of: celebrationID) { _, _ in celebrateIfNew() }
    }

    // MARK: - Laughing eyes (lot 1.6)

    /// When the bars start coming back, counted from the spring into ^ ^: about 0.4 s for
    /// that spring to settle, then 0.6 s of ^ ^ fully drawn.
    private static let smileHold: TimeInterval = 1.0

    /// Plays the laughing eyes once per written dictation. Nothing waits for it: the text
    /// is already in and the keys are already back when it starts.
    private func celebrateIfNew() {
        guard celebrationID > Self.lastCelebratedID else { return }
        Self.lastCelebratedID = celebrationID
        if reduceMotion {
            // Reduce Motion: fades only, no stroke moves.
            strokes = InkMicGlyph.smile.strokes
            glyphOpacity = 0
            // Next run-loop turn: set in the same pass as the 0, the fade would start from
            // the 1 already drawn and show nothing.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) { glyphOpacity = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.15)) { glyphOpacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    strokes = InkMicGlyph.bars.strokes
                    withAnimation(.easeOut(duration: 0.15)) { glyphOpacity = 1 }
                }
            }
        } else {
            // The ✓ the listening screen ended on, in the same place, then the smile.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { strokes = InkMicGlyph.check.strokes }
            // Next run-loop turn, so the ✓ is drawn once: in the same pass, SwiftUI would
            // spring from the bars it last drew and the ✓ would never show.
            DispatchQueue.main.async {
                withAnimation(Self.morphSpring) { strokes = InkMicGlyph.smile.strokes }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.smileHold) {
                    withAnimation(Self.morphSpring) { strokes = InkMicGlyph.bars.strokes }
                }
            }
        }
    }

    /// The mode's mark on a small ink disc at the bars' lower right. Ink and not the old
    /// white disc: there is no blue pill behind it any more for white to stand out from.
    @ViewBuilder
    private var armedBadge: some View {
        if let badge {
            badgeContent(badge)
                .foregroundStyle(Color.ouisprBackground)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.ouisprAccentText))
                .offset(x: 14, y: 10)
        }
    }

    @ViewBuilder
    private func badgeContent(_ badge: SmartModeBadge) -> some View {
        switch badge {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 8.5, weight: .bold))
        case .text(let value):
            Text(verbatim: value)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
#endif
