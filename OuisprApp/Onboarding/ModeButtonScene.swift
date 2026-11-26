// OuisprApp/Onboarding/ModeButtonScene.swift
// What's new: Home's mode button, drawn and looping (audit of 26 Nov 2026).
import SwiftUI
import OuisprCore

/// What's new's first page since the mode button replaced the long press on Home's mic:
/// a tap on the button chooses the mode of the next dictation, a long press on a row makes
/// it the default. The keyboard's long-press fan is unchanged, so the onboarding keeps its
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
            line: Text("Tap the button at the top left: you choose the mode of the next dictation. Long press a mode: it becomes your default.",
                       comment: "What's new, first page: the line under the title. Tap = mode of the next dictation, long press on a row = default mode."),
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

/// The scene's clock, in seconds of its 7 s loop.
enum ModeButtonScript {
    static let loop = 7.0
    /// Under Reduce Motion: the menu open, List chosen and made the default.
    static let still = 5.8
    static let firstTap = 1.0
    static let chooseList = 2.4
    static let secondTap = 3.6
    static let pressStart = 4.6
    static let pressEnd = 5.3
    static let close = 6.3
}

/// One frame of the scene: Home's top bar, the menu the button stretches into, and a
/// finger.
private struct ModeButtonScene: View {
    let time: Double
    private typealias Script = ModeButtonScript

    private static let rows: [(icon: String, name: LocalizedStringKey)] = [
        ("circle", "Normal"), ("list.bullet", "List"), ("character.bubble", "Translate")
    ]

    /// The width the mock-ups are drawn at, as in the other scenes, and the part of the
    /// screen the card shows: the top bar and the open menu.
    private static let screenWidth = SmartModesSceneMetrics.screenWidth
    private static let screenHeight: CGFloat = 300

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
        let button = CGPoint(x: 38, y: 74)
        return ZStack(alignment: .topLeading) {
            Color.ouisprBackground
            topBar
            menu
                .scaleEffect(0.15 + 0.85 * menuOpen, anchor: .topLeading)
                .opacity(menuOpen)
                .offset(x: 16, y: 52)
            finger
                .position(fingerPosition(button: button))
                .opacity(fingerOpacity)
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Image(systemName: listChosen ? "list.bullet" : "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(listChosen ? Color.ouisprAccent : Color.ouisprTextPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.ouisprSurface).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
                .opacity(menuOpen > 0.01 ? 0 : 1)
            Spacer()
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.ouisprTextPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.ouisprSurface).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
        }
        .padding(.horizontal, 16)
        .padding(.top, 52)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                let selected = index == (listChosen ? 1 : 0)
                HStack(spacing: 10) {
                    Image(systemName: row.icon)
                        .foregroundStyle(selected ? Color.ouisprAccent : Color.ouisprTextSecondary)
                        .frame(width: 20)
                    Text(row.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ouisprTextPrimary)
                    if index == 1 && isDefault {
                        Text("default")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.ouisprAccent)
                    }
                    Spacer(minLength: 6)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.ouisprAccent)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.06 : 0)))
            }
        }
        .padding(6)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.ouisprSurface)
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4))
    }

    /// A fingertip, with the ring of a long press filling around it.
    private var finger: some View {
        ZStack {
            Circle().fill(Color.ouisprTextPrimary.opacity(0.18)).frame(width: 34, height: 34)
            Circle()
                .trim(from: 0, to: pressProgress)
                .stroke(Color.ouisprAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 42, height: 42)
        }
        .scaleEffect(isTapping ? 0.85 : 1)
    }

    // MARK: Timing

    private func ramp(_ from: Double, _ duration: Double) -> Double {
        let k = min(1, max(0, (time - from) / duration))
        return k * k * (3 - 2 * k)
    }

    /// 0 closed, 1 open: open after each tap on the button, closed after the choice and
    /// at the end.
    private var menuOpen: Double {
        if time < Script.chooseList + 0.2 { return ramp(Script.firstTap, 0.3) }
        if time < Script.secondTap { return 1 - ramp(Script.chooseList + 0.2, 0.3) }
        if time < Script.close { return ramp(Script.secondTap, 0.3) }
        return 1 - ramp(Script.close, 0.3)
    }

    private var listChosen: Bool { time >= Script.chooseList + 0.2 }
    private var isDefault: Bool { time >= Script.pressEnd }

    private var pressProgress: Double {
        guard time >= Script.pressStart, time < Script.close else { return 0 }
        return min(1, (time - Script.pressStart) / (Script.pressEnd - Script.pressStart))
    }

    private var isTapping: Bool {
        [Script.firstTap, Script.chooseList, Script.secondTap].contains { abs(time - $0) < 0.12 }
            || (time >= Script.pressStart && time < Script.pressEnd)
    }

    private var fingerOpacity: Double {
        if time < 0.5 { return ramp(0.3, 0.2) }
        if time > Script.pressEnd + 0.4 { return 1 - ramp(Script.pressEnd + 0.4, 0.3) }
        return 1
    }

    /// On the button, then on the List row, back on the button, on List again.
    private func fingerPosition(button: CGPoint) -> CGPoint {
        let list = CGPoint(x: 16 + 6 + 70, y: 52 + 6 + 44 + 22)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        let start = CGPoint(x: button.x + 40, y: button.y + 60)
        if time < Script.firstTap { return lerp(start, button, ramp(0.4, 0.5)) }
        if time < Script.chooseList { return lerp(button, list, ramp(Script.firstTap + 0.5, 0.6)) }
        if time < Script.secondTap { return lerp(list, button, ramp(Script.chooseList + 0.4, 0.6)) }
        return lerp(button, list, ramp(Script.secondTap + 0.4, 0.5))
    }
}
