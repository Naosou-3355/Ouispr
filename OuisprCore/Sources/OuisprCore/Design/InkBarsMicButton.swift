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
    public let onTap: () -> Void

    public init(status: DictationStatus, badge: SmartModeBadge? = nil, onTap: @escaping () -> Void) {
        self.status = status
        self.badge = badge
        self.onTap = onTap
    }

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
                InkMicBars()
                    .fill(Color.ouisprInk)
                    .frame(width: Self.glyphSide, height: Self.glyphSide)
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
