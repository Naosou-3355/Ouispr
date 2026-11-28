// OuisprApp/Onboarding/ModeButtonScene.swift
// What's new: Home's mode button, drawn and looping (audit of 26 Nov 2026).
import SwiftUI
import OuisprCore

/// What's new's first page since the mode button replaced the long press on Home's mic:
/// the mode's name under the character is the button, and a tap on it chooses the mode of
/// the next dictation (« Banc Ouispr épuré », 27 Nov 2026). The default is set in the same
/// menu. The keyboard's long-press fan is unchanged, so the onboarding keeps its
/// own Smart Modes scene; only What's new, which announced the removed dial, changes.
struct ModeButtonScenePage: View {
    var eyebrow: Text?
    @ObservedObject var modelManager: ModelManager
    let modelIdentifier: String
    let onNext: () -> Void

    var body: some View {
        OnboardingScenePage(
            eyebrow: eyebrow,
            title: Text("Choose the mode before you speak",
                        comment: "What's new, first page: title about Home's mode button, top left (audit of 26 Nov 2026)."),
            line: Text("Tap the mode's name under the character: you choose the mode of the next dictation. Your default mode is in the same menu.",
                       comment: "What's new, first page: the line under the title. The mode's name under Home's character opens a menu: the next dictation's mode, and a submenu for the default."),
            modelManager: modelManager,
            modelIdentifier: modelIdentifier,
            onNext: onNext
        ) {
            FeatureSceneCard(phoneEnd: .top, loopSeconds: ModeButtonScript.loop,
                             stillSeconds: ModeButtonScript.still) { time in
                ModeButtonScene(time: time)
            }
        }
    }
}

/// The scene's clock, in seconds of its 5 s loop.
enum ModeButtonScript {
    static let loop = 5.0
    /// Under Reduce Motion: the menu open, Normal ticked, the finger on Liste.
    static let still = 2.2
    static let firstTap = 1.0
    static let chooseList = 2.6
}

/// One frame of the scene: the mode's name under Home's character, the system menu it
/// opens, and a finger.
private struct ModeButtonScene: View {
    let time: Double
    private typealias Script = ModeButtonScript

    private static let rows: [(icon: String, name: LocalizedStringKey)] = [
        ("text.alignleft", "Normal"), ("list.bullet", "List"), ("globe", "Translate")
    ]

    /// The width the mock-ups are drawn at, as in the other scenes, and the part of the
    /// screen the card shows: the mode's line and the open menu.
    private static let screenWidth = SmartModesSceneMetrics.screenWidth
    private static let screenHeight: CGFloat = 300
    private static let labelY: CGFloat = 56
    private static let menuWidth: CGFloat = 230
    private static let rowHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            screen
                .frame(width: Self.screenWidth, height: Self.screenHeight, alignment: .topLeading)
                .clipped()
                .scaleEffect(geometry.size.width / Self.screenWidth, anchor: .topLeading)
        }
        .aspectRatio(Self.screenWidth / Self.screenHeight, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var screen: some View {
        let label = CGPoint(x: Self.screenWidth / 2, y: Self.labelY)
        return ZStack(alignment: .top) {
            Color.ouisprBackground
            modeLabel
                .position(label)
            menu
                .scaleEffect(0.6 + 0.4 * menuOpen, anchor: .top)
                .opacity(menuOpen)
                .offset(y: Self.labelY + 26)
            finger
                .position(fingerPosition(label: label))
                .opacity(fingerOpacity)
        }
    }

    // MARK: Pieces

    /// « Mode Normal ⌄ » in its glass capsule, as `HomeModeMenu` draws it.
    private var modeLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: listChosen ? "list.bullet" : "text.alignleft")
                .foregroundStyle(Color.ouisprAccentText)
            Text("Mode \(Text(listChosen ? "List" : "Normal").foregroundStyle(Color.ouisprTextPrimary))")
                .foregroundStyle(Color.ouisprTextSecondary)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ouisprTextTertiary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .frame(height: 44)
        .ouisprGlassBar()
    }

    /// The system menu: the tick on the mode that runs, the glyph on the others.
    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 12) {
                    Image(systemName: index == 0 ? "checkmark" : row.icon)
                        .foregroundStyle(Color.ouisprAccentText)
                        .frame(width: 20)
                    Text(row.name)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.ouisprTextPrimary)
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 14)
                .frame(height: Self.rowHeight)
            }
            Divider().padding(.horizontal, 14)
            HStack(spacing: 12) {
                Image(systemName: "pin")
                    .foregroundStyle(Color.ouisprAccentText)
                    .frame(width: 20)
                Text("Default mode")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.ouisprTextPrimary)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ouisprTextTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.rowHeight)
        }
        .padding(.vertical, 6)
        .frame(width: Self.menuWidth)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.ouisprSurface)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4))
    }

    /// A fingertip.
    private var finger: some View {
        Circle().fill(Color.ouisprTextPrimary.opacity(0.18)).frame(width: 34, height: 34)
            .scaleEffect(isTapping ? 0.85 : 1)
    }

    // MARK: Timing

    private func ramp(_ from: Double, _ duration: Double) -> Double {
        let k = min(1, max(0, (time - from) / duration))
        return k * k * (3 - 2 * k)
    }

    /// 0 closed, 1 open: open after the tap on the name, closed after the choice.
    private var menuOpen: Double {
        if time < Script.chooseList + 0.2 { return ramp(Script.firstTap, 0.3) }
        return 1 - ramp(Script.chooseList + 0.2, 0.3)
    }

    private var listChosen: Bool { time >= Script.chooseList + 0.2 }

    private var isTapping: Bool {
        [Script.firstTap, Script.chooseList].contains { abs(time - $0) < 0.12 }
    }

    private var fingerOpacity: Double {
        if time < 0.5 { return ramp(0.3, 0.2) }
        if time > Script.chooseList + 0.5 { return 1 - ramp(Script.chooseList + 0.5, 0.3) }
        return 1
    }

    /// On the name, then on the List row.
    private func fingerPosition(label: CGPoint) -> CGPoint {
        let list = CGPoint(x: label.x - 40, y: Self.labelY + 26 + 6 + Self.rowHeight * 1.5)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        let start = CGPoint(x: label.x + 50, y: label.y + 90)
        if time < Script.firstTap { return lerp(start, label, ramp(0.4, 0.5)) }
        return lerp(label, list, ramp(Script.firstTap + 0.5, 0.6))
    }
}
