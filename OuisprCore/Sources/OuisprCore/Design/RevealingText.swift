#if os(iOS)
// OuisprCore/Sources/OuisprCore/Design/RevealingText.swift
// A dictated text that comes into focus word by word.
import SwiftUI

/// Shows `text`, each word going from blurred to sharp in reading order (bench 3).
///
/// WHY it is an animation after the fact and not a live transcript: the speech
/// engines hand over one text when the dictation ends. The words were never
/// available one by one, so this replays them. A true live transcript is a later
/// step of the roadmap.
///
/// With Reduce Motion, or for a text longer than `WordRevealPlan.maximumAnimatedWords`,
/// the whole text fades in once.
///
/// To replay it for a new text, give the view a new identity: `.id(text)`.
public struct RevealingText: View {
    private let text: String
    private let plan: WordRevealPlan
    private let font: Font

    @State private var isShown = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The gap between two words: a quarter of the 28 pt the font has at the default
    /// text size, growing with it.
    @ScaledMetric(relativeTo: .title) private var wordSpacing: CGFloat = 7
    /// The gap between two lines, which with the font's own height gives the 34 pt
    /// line of the mock-ups at the default text size.
    @ScaledMetric(relativeTo: .title) private var lineSpacing: CGFloat = 1

    /// - Parameters:
    ///   - font: the recording screen's dictation font by default; the cards of Home and
    ///     the history pass their own, with the gap between words that goes with it.
    public init(_ text: String, font: Font = .ouisprDictation, wordSpacing: CGFloat = 7, lineSpacing: CGFloat = 1) {
        self.text = text
        self.plan = WordRevealPlan(text: text)
        self.font = font
        _wordSpacing = ScaledMetric(wrappedValue: wordSpacing, relativeTo: .title)
        _lineSpacing = ScaledMetric(wrappedValue: lineSpacing, relativeTo: .title)
    }

    public var body: some View {
        Group {
            if plan.animatesWordByWord && !reduceMotion {
                words
            } else {
                Text(verbatim: text)
                    .font(font)
                    .lineSpacing(lineSpacing)
                    .multilineTextAlignment(.leading)
                    .opacity(isShown ? 1 : 0)
                    .animation(.easeOut(duration: Motion.standard), value: isShown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element reading the whole text, not one stop per word.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .onAppear { isShown = true }
    }

    private var words: some View {
        WordFlowLayout(wordSpacing: wordSpacing, lineSpacing: lineSpacing) {
            ForEach(Array(indexedTokens.enumerated()), id: \.offset) { _, item in
                switch item.token {
                case .word(let word):
                    Text(verbatim: word)
                        .font(font)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(isShown ? 1 : 0)
                        .blur(radius: isShown ? 0 : 6)
                        .animation(
                            .easeOut(duration: WordRevealPlan.wordDuration)
                                .delay(plan.delay(forWordAt: item.wordIndex)),
                            value: isShown
                        )
                case .lineBreak:
                    Color.clear
                        .frame(width: 0, height: 0)
                        .layoutValue(key: ForcesLineBreak.self, value: true)
                }
            }
        }
    }

    /// Every token with the rank of its word, which is what its delay is read from.
    private var indexedTokens: [(token: WordRevealPlan.Token, wordIndex: Int)] {
        var wordIndex = 0
        return plan.tokens.map { token -> (token: WordRevealPlan.Token, wordIndex: Int) in
            defer { if case .word = token { wordIndex += 1 } }
            return (token, wordIndex)
        }
    }
}

/// Marks a subview of `WordFlowLayout` as the end of a line.
private struct ForcesLineBreak: LayoutValueKey {
    static let defaultValue = false
}

/// Lays words out like a paragraph: left to right, wrapping at the available width.
///
/// WHY a custom layout and not one `Text`: a `Text` is one view, and blurring one
/// word of it is not something SwiftUI offers before iOS 18. One view per word is
/// what lets each of them animate on its own.
///
/// Left to right only. Ouispr dictates French and English today; a right-to-left
/// language would need the rows mirrored.
private struct WordFlowLayout: Layout {
    let wordSpacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let arrangement = arrange(subviews, width: width)
        return CGSize(
            width: width.isFinite ? width : arrangement.usedWidth,
            height: arrangement.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let frame = arrangement.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private struct Arrangement {
        var frames: [CGRect] = []
        var usedWidth: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> Arrangement {
        var arrangement = Arrangement()
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        // The height of a line with nothing on it: an empty line the text asked for
        // still takes the room of a line.
        var lastWordHeight: CGFloat = 0

        func endRow() {
            cursorY += max(rowHeight, lastWordHeight) + lineSpacing
            cursorX = 0
            rowHeight = 0
        }

        for subview in subviews {
            if subview[ForcesLineBreak.self] {
                arrangement.frames.append(CGRect(x: cursorX, y: cursorY, width: 0, height: 0))
                endRow()
                continue
            }
            // A word wider than the line is given the line's width and wraps inside it.
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if cursorX > 0, cursorX + size.width > width {
                endRow()
            }
            arrangement.frames.append(CGRect(x: cursorX, y: cursorY, width: size.width, height: size.height))
            cursorX += size.width + wordSpacing
            rowHeight = max(rowHeight, size.height)
            lastWordHeight = size.height
            arrangement.usedWidth = max(arrangement.usedWidth, cursorX - wordSpacing)
        }
        arrangement.height = cursorY + rowHeight
        return arrangement
    }
}

#Preview("Short") {
    RevealingText("Dis à Camille que je serai en retard, vers dix-huit heures.")
        .padding(24)
        .background(Color.ouisprBackground)
}

#Preview("Two paragraphs") {
    RevealingText("Bonjour,\nje vous confirme notre rendez-vous de demain à neuf heures.\nBonne journée.")
        .padding(24)
        .background(Color.ouisprBackground)
}
#endif
