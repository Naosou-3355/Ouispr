// OuisprKeyboard/Views/RecordingOverlay.swift
import QuartzCore
import SwiftUI
import OuisprCore

/// The listening screen that replaces the keyboard while a dictation runs.
///
/// Lot 1.4 (Alex's keyboard bench, 27 Nov 2026, « épuré ») put the ink character's two eyes
/// in the middle and a one-word state under them, in place of the waveform, the timer and
/// the glass pills. Lot 1.5 (Alex's device feedback, same day) adds a fine ink wave that
/// follows the voice under the eyes, and puts the two actions side by side below: ✕ on
/// the left, ✓ on the right.
///
/// - .requested: the eyes at rest, the wave hidden, « J'écoute », ✓ greyed, ✕
/// - .recording: the eyes stretch with the voice and blink, the wave follows it,
///   « J'écoute », ✓ and ✕
/// - .transcribing / .processing: the eyes glance from side to side, « Transcription »,
///   ✓ greyed and no ✕ (neither stage can be cancelled, #267)
///
/// .ready has no face of its own: the overlay leaves as soon as the text is in and the
/// keys come back at once (lot 1.5 dropped the laughing eyes that would have held them).
/// For the instant it may linger, it shows the resting eyes and a greyed ✓.
///
/// WHY it replaces the keyboard: when recording, the keyboard area turns into the
/// listening UI. This prevents accidental key presses during dictation and gives clear
/// feedback that the mic is live.
///
/// WHY the eyes and the wave are driven by `KeyboardWaveformDriver` and not a
/// `TimelineView`: a `TimelineView` proved fragile inside the keyboard extension after
/// suspension and resume. The driver's display link starts and stops with the overlay,
/// and it already carries the voice's levels; both read them on each of its ticks.
struct RecordingOverlay: View {
    /// The stage to draw — `KeyboardState.displayedDictationStatus`, not the raw
    /// dictation status (#309). The two differ for at most half a second, while a
    /// transcription that returned faster than the eye can read it is held on screen.
    ///
    /// The probes below therefore report what was *drawn*, which is what they are for.
    /// The pipeline's own transitions are logged unchanged by `KeyboardState`, and the
    /// hold itself by its `transcribingHoldArmed` / `transcribingHoldReleased` probes,
    /// so a log still says both what happened and what the user saw.
    let dictationStatus: DictationStatus
    /// Only reported in the probes: the eyes read the driver's smoothed levels.
    let waveformEnergy: [Float]
    /// Passed through to the eyes, which observe it; the overlay does not.
    let waveformDriver: KeyboardWaveformDriver
    let onCancel: () -> Void
    let onStop: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The armed Smart Mode, or nil for Normal (#79).
    ///
    /// **This is the indicator that makes a sticky mode safe.** The mode survives
    /// restarts and can have been armed a week ago; the mic's badge names it, but by
    /// the time the overlay is up the mic is gone and the badge with it. Naming it here
    /// means the user reads "List" while speaking, with the cancel button one tap
    /// away — which is the difference between a setting they forgot and a setting that
    /// cost them a dictation.
    var armedSmartMode: SmartMode?

    @State private var instanceID = String(UUID().uuidString.prefix(8))

    var body: some View {
        VStack(spacing: 0) {
            // The armed mode, at the top where the toolbar's mode name was. The band
            // keeps its height when there is no mode, so nothing below moves.
            armedModeBadge
                .frame(height: isCompactHeight ? 24 : 32)
                .padding(.top, 8)

            // WHY Spacers and no GeometryReader: on the first frame the hosting view may
            // still be at toolbar height (52 pt) before growing to the keyboard's. A
            // GeometryReader would measure the old frame and draw everything squeezed at
            // the top for a frame; fixed sizes between Spacers are centred from the first.
            Spacer(minLength: 0)

            KeyboardInkFace(status: dictationStatus, driver: waveformDriver, isCompactHeight: isCompactHeight)

            stateWord
                .padding(.top, 8)
                // Capped so a large text size cannot push the buttons under the
                // keyboard's edge in landscape, where the room is about 4 pt.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)

            Spacer(minLength: 0)

            actionRow
                .padding(.bottom, isCompactHeight ? 8 : 16)
        }
        .frame(maxWidth: .infinity)
        .background(GeometryReader { proxy in
            // The overlay's laid-out size, once per overlay (lot 1.5): the proof on a
            // device log that the listening screen had its room, the face included.
            Color.clear.onAppear {
                PersistentLog.log(.diagnosticProbe(
                    component: "RecordingOverlay",
                    instanceID: instanceID,
                    action: "laidOut",
                    details: "size=\(Int(proxy.size.width))x\(Int(proxy.size.height)) status=\(dictationStatus.rawValue) compact=\(isCompactHeight)"
                ))
            }
        })
        .onAppear {
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "onAppear",
                details: "status=\(dictationStatus.rawValue) energyCount=\(waveformEnergy.count)"
            ))
            PersistentLog.log(.overlayBodyEvaluated(
                status: dictationStatus.rawValue,
                showsOverlay: true,
                energyCount: waveformEnergy.count
            ))
        }
        .onDisappear {
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "onDisappear",
                details: "status=\(dictationStatus.rawValue)"
            ))
        }
        .onChange(of: dictationStatus) { _, newStatus in
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "statusChanged",
                details: "newStatus=\(newStatus.rawValue) energyCount=\(waveformEnergy.count)"
            ))
        }
    }

    // MARK: - Pieces

    /// True in iPhone landscape, where the keyboard and its bar are about 222 pt tall.
    ///
    /// WHY: the portrait sizes add up to about 242 pt and the hosting view does not clip,
    /// so in landscape the buttons would hang under the keyboard's edge. They drop to
    /// 48 pt, the wave to 16 pt and the band and paddings tighten (about 205 pt).
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    /// The two buttons' diameter: 56 pt, 48 pt in landscape. Both on the 8 pt grid and
    /// above Apple's 44 pt minimum target.
    private var buttonDiameter: CGFloat { isCompactHeight ? 48 : 56 }

    /// One word under the eyes, 13 pt in the quiet grey. It holds the room of the longer
    /// word, so the eyes above never move when it changes, and it says nothing at the end.
    private var stateWord: some View {
        ZStack {
            Text("Listening", comment: "One word under the eyes on the keyboard's listening screen, while it listens: « J'écoute » (lot 1.4).").hidden()
            Text("Transcribing", comment: "One word under the eyes on the keyboard's listening screen, while the words are worked out: « Transcription » (lot 1.4).").hidden()
            switch dictationStatus {
            case .requested, .recording:
                Text("Listening", comment: "One word under the eyes on the keyboard's listening screen, while it listens: « J'écoute » (lot 1.4).")
            case .transcribing, .processing:
                Text("Transcribing", comment: "One word under the eyes on the keyboard's listening screen, while the words are worked out: « Transcription » (lot 1.4).")
            case .idle, .ready, .failed:
                EmptyView()
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.ouisprTextTertiary)
        .lineLimit(1)
    }

    /// ✕ on the left, ✓ on the right, the same size, symmetric about the centre line.
    ///
    /// WHY 64 pt between them (lot 1.5): the brief asked for well-separated targets,
    /// centres about 120 pt apart. 56 + 64 = 120 at the default size; in landscape the
    /// 48 pt buttons keep the same gap. Each target is the whole disc, so no touch can
    /// land on both, and the gap is wide enough for a thumb that misses by half a disc.
    private var actionRow: some View {
        // Also after a failure: if the overlay is still up then, the ✕ is the way out.
        let cancellable = dictationStatus == .requested || dictationStatus == .recording
            || dictationStatus == .failed
        let confirmable = dictationStatus == .recording
        return HStack(spacing: 64) {
            ListeningActionButton(
                kind: .cancel,
                diameter: buttonDiameter,
                isEnabled: cancellable
            ) {
                HapticFeedback.recordingStopped()
                onCancel()
            }
            // Hidden but holding its room while the words are worked out, which cannot
            // be cancelled (#267): the ✓ stays where it was.
            .opacity(cancellable ? 1 : 0)
            .accessibilityHidden(!cancellable)

            ListeningActionButton(
                kind: .confirm,
                diameter: buttonDiameter,
                isEnabled: confirmable
            ) {
                HapticFeedback.recordingStopped()
                onStop()
            }
        }
    }

    /// The armed mode's name (#79). Renders nothing for Normal: an "off" state announced
    /// on every dictation is noise, and the absence is already unambiguous.
    @ViewBuilder
    private var armedModeBadge: some View {
        if let armedSmartMode {
            HStack(spacing: 5) {
                Image(systemName: armedSmartMode.icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(armedSmartMode.localizedDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.ouisprAccentText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.ouisprAccent.opacity(0.14)))
        } else {
            Color.clear
        }
    }
}

// MARK: - Buttons

/// One of the listening screen's two round buttons (lot 1.5).
///
/// ✓ is the main action, a full ink disc with the tick in the background's colour, like
/// the app's ink buttons. ✕ is the secondary one: a quiet neutral disc with the cross in
/// the primary text colour, the same size so the row reads as a pair.
private struct ListeningActionButton: View {
    enum Kind {
        case cancel, confirm
    }

    let kind: Kind
    let diameter: CGFloat
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(kind == .confirm ? Color.ouisprInk : Color.ouisprTextPrimary.opacity(0.08))
                Image(systemName: kind == .confirm ? "checkmark" : "xmark")
                    .font(.system(size: diameter * 0.36, weight: .semibold))
                    .foregroundStyle(kind == .confirm ? Color.ouisprBackground : Color.ouisprTextPrimary)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            // Greyed while a tap would do nothing: ✓ before the mic is live and while
            // the words are worked out.
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.92, pressedOpacity: 0.75))
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var label: Text {
        switch kind {
        case .cancel:
            return Text("Cancel", comment: "VoiceOver name of the ✕ that cancels a dictation on the keyboard's listening screen (lot 1.4).")
        case .confirm:
            return Text("Confirm", comment: "VoiceOver name of the ✓ that ends a dictation and writes it, on the keyboard's listening screen: « Valider » (lot 1.5).")
        }
    }
}

// MARK: - Face

/// The ink character's two eyes and, under them while listening, the voice's wave.
///
/// WHY SHAPE VIEWS AND NOT A CANVAS (lot 1.5): in lot 1.4 the eyes were a `Canvas`
/// stroking with a gradient shading, the app's renderer. On Alex's iPhone they did not
/// appear at all, while the simulator drew them in both Debug and Release. Everything
/// the keyboard has shown on device (the mic bars, the ink disc, the old waveform's flat
/// colours) is a flat fill. So the eyes are two `Capsule`s and the wave one stroked
/// `Shape`, both in flat ink, the drawing the keyboard already proved on the device. The
/// geometry is unchanged: it still comes from `InkGeometry`.
///
/// Redrawn on each tick of the driver's display link (`renderTick`), which runs while
/// recording and transcribing and stops otherwise: the face then holds its shape and
/// costs nothing. Reduce Motion keeps the eyes still and unstretched and the wave still at
/// its quiet floor; only the state word and the buttons change.
private struct KeyboardInkFace: View {
    let status: DictationStatus
    @ObservedObject var driver: KeyboardWaveformDriver
    let isCompactHeight: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The eyes' drawing scale: the app's resting eyes at 1.25, about 12 pt wide and
    /// 22 pt tall each, 48 pt apart. Fully stretched, an eye's top sits about 33 pt above
    /// the centre, inside the 72 pt frame's 36.
    private static let scale: CGFloat = 1.25
    private static let eyesHeight: CGFloat = 72
    private static let waveWidth: CGFloat = 144
    private static let waveSamples = 49

    var body: some View {
        // Read so that each tick of the display link redraws the face.
        _ = driver.renderTick
        let level = voiceLevel
        let time = CACurrentMediaTime()
        return VStack(spacing: isCompactHeight ? 4 : 8) {
            eyes(level: level, time: time)
                .frame(width: 144, height: Self.eyesHeight)
            InkWaveLine(heights: waveHeights(level: level, time: time))
                .stroke(Color.ouisprInk, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: Self.waveWidth, height: isCompactHeight ? 16 : 24)
                // Only while listening: it holds its room otherwise, so nothing moves.
                .opacity(status == .recording ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The voice's level, 0 to 1: the mean of the driver's smoothed levels, doubled
    /// because speech sits mostly under 0.5. A level that is not a number reads as silence.
    private var voiceLevel: Double {
        guard status == .recording, !reduceMotion else { return 0 }
        let levels = driver.displayLevels
        guard !levels.isEmpty else { return 0 }
        let mean = Double(levels.reduce(0, +)) / Double(levels.count)
        guard mean.isFinite else { return 0 }
        return min(1, max(0, 2 * mean))
    }

    private func eyes(level: Double, time: CFTimeInterval) -> some View {
        let shapes = eyesFrame(level: level, time: time).shapes
        return ZStack {
            ForEach(shapes.indices, id: \.self) { index in
                if case let .stroke(points, width) = shapes[index], let first = points.first, let last = points.last {
                    // A vertical stroke with round caps is a capsule: as long as the line
                    // plus one width, as wide as the stroke, centred on its midpoint.
                    Capsule()
                        .fill(Color.ouisprInk)
                        .frame(
                            width: width * Self.scale,
                            height: (abs(last.y - first.y) + width) * Self.scale
                        )
                        .offset(
                            x: (first.x + last.x) / 2 * Self.scale,
                            y: (first.y + last.y) / 2 * Self.scale
                        )
                }
            }
        }
    }

    private func eyesFrame(level: Double, time: CFTimeInterval) -> InkFrame {
        guard !reduceMotion else {
            return InkGeometry.listeningEyes(stretch: 0, gazeX: 0, blink: 0)
        }
        switch status {
        case .recording:
            return InkGeometry.listeningEyes(
                stretch: level,
                gazeX: 0,
                blink: InkGeometry.keyboardBlink(at: time)
            )
        case .transcribing, .processing:
            return InkGeometry.listeningEyes(stretch: 0, gazeX: InkGeometry.keyboardSweep(at: time), blink: 0)
        case .idle, .requested, .ready, .failed:
            return InkGeometry.listeningEyes(stretch: 0, gazeX: 0, blink: 0)
        }
    }

    /// The wave travels at about one period a second; under Reduce Motion it stays put.
    private func waveHeights(level: Double, time: CFTimeInterval) -> [Double] {
        let phase = reduceMotion ? 0 : -2 * Double.pi * 0.8 * time.truncatingRemainder(dividingBy: 1000)
        return InkGeometry.keyboardWave(level: level, phase: phase, samples: Self.waveSamples)
    }
}

/// A line through evenly spaced heights, -1 at the top of its frame and 1 at the bottom.
private struct InkWaveLine: Shape {
    let heights: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard heights.count > 1 else { return path }
        let halfHeight = rect.height / 2
        for (index, height) in heights.enumerated() {
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(heights.count - 1),
                y: rect.midY - halfHeight * CGFloat(height)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
