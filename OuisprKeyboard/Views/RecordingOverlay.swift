// OuisprKeyboard/Views/RecordingOverlay.swift
import QuartzCore
import SwiftUI
import OuisprCore

/// The listening screen that replaces the keyboard while a dictation runs.
///
/// Lot 1.4 (Alex's keyboard bench, 27 Nov 2026, « épuré »): the ink character's two eyes
/// in the middle, a one-word state under them, the ink disc with its stop square below,
/// and the ✕ that cancels under the disc. The waveform, the timer and the glass pills it
/// replaces are gone: the app's own recording screen dropped them first.
///
/// - .requested: the eyes at rest, « J'écoute », the disc greyed (nothing to stop yet), ✕
/// - .recording: the eyes stretch with the voice and blink, « J'écoute », stop, ✕
/// - .transcribing / .processing: the eyes glance from side to side, « Transcription »,
///   the disc greyed and no ✕ (neither stage can be cancelled, #267)
/// - .ready: the laughing eyes, no word
///
/// WHY it replaces the keyboard: when recording, the keyboard area turns into the
/// listening UI. This prevents accidental key presses during dictation and gives clear
/// feedback that the mic is live.
///
/// WHY the eyes are driven by `KeyboardWaveformDriver` and not a `TimelineView`: a
/// `TimelineView` proved fragile inside the keyboard extension after suspension and
/// resume. The driver's display link starts and stops with the overlay, and it already
/// carries the voice's levels; the eyes read them on each of its ticks.
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
                .frame(height: isCompactHeight ? 28 : 36)
                .padding(.top, isCompactHeight ? 2 : 8)

            // WHY Spacers and no GeometryReader: on the first frame the hosting view may
            // still be at toolbar height (52 pt) before growing to the keyboard's. A
            // GeometryReader would measure the old frame and draw everything squeezed at
            // the top for a frame; fixed sizes between Spacers are centred from the first.
            Spacer(minLength: 0)

            KeyboardInkEyes(status: dictationStatus, driver: waveformDriver)
                .frame(width: 120, height: 70)

            stateWord
                .padding(.top, 6)

            Spacer(minLength: 0)

            InkMicButton(phase: discPhase, size: isCompactHeight ? 44 : 56) {
                HapticFeedback.recordingStopped()
                onStop()
            }
            .accessibilityLabel(Text("Stop", comment: "VoiceOver name of the ink disc that ends a dictation on the keyboard's listening screen (lot 1.4)."))

            cancelButton
                .padding(.top, isCompactHeight ? 0 : 4)
                .padding(.bottom, isCompactHeight ? 0 : 4)
        }
        .frame(maxWidth: .infinity)
        .background(Color.clear)
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
    /// WHY: the portrait sizes add up to about 245 pt and the hosting view does not clip,
    /// so in landscape the ✕ would hang under the keyboard's edge. The disc drops to
    /// 44 pt, Apple's minimum target, and the band and paddings tighten (about 203 pt).
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    /// The disc's state: the stop square while recording, the bars greyed whenever a
    /// tap would do nothing (still starting, or working out the words).
    private var discPhase: InkMicButton.Phase {
        dictationStatus == .recording ? .listening : .working
    }

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

    /// The ✕ under the disc: a bare glyph in a 44 pt target (Apple's minimum). Hidden but
    /// holding its room while the words are worked out, which cannot be cancelled (#267).
    private var cancelButton: some View {
        // Also after a failure: if the overlay is still up then, the ✕ is the way out.
        let cancellable = dictationStatus == .requested || dictationStatus == .recording
            || dictationStatus == .failed
        return Button {
            HapticFeedback.recordingStopped()
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ouisprTextSecondary)
                .frame(width: 44, height: 44)
                // A keyboard extension delivers no touch on fully transparent pixels:
                // without this fill only the ✕'s strokes would answer.
                .background(Color.black.opacity(0.001))
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .opacity(cancellable ? 1 : 0)
        .disabled(!cancellable)
        .accessibilityLabel(Text("Cancel", comment: "VoiceOver name of the ✕ that cancels a dictation on the keyboard's listening screen (lot 1.4)."))
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

// MARK: - Eyes

/// The ink character's two eyes, drawn from `InkGeometry` the way the app draws them.
///
/// Redrawn on each tick of the driver's display link (`renderTick`), which runs while
/// recording and transcribing and stops otherwise: the eyes then hold their shape and
/// cost nothing. Reduce Motion keeps them still and unstretched; only the state word and
/// the disc change.
private struct KeyboardInkEyes: View {
    let status: DictationStatus
    @ObservedObject var driver: KeyboardWaveformDriver

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The eyes' drawing scale: the app's resting eyes at 1.25, about 12 pt wide and
    /// 22 pt tall each, 48 pt apart, in a 120 × 70 frame: fully stretched, an eye's top
    /// sits about 33 pt above the centre, inside the frame's 35.
    private static let scale: CGFloat = 1.25

    var body: some View {
        // Read so that each tick of the display link redraws the canvas.
        let tick = driver.renderTick
        let frame = currentFrame(tick: tick)
        return Canvas { context, size in
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: Self.scale, y: Self.scale)
            InkFrameRenderer.draw(frame, in: &context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func currentFrame(tick: Int) -> InkFrame {
        if status == .ready {
            return InkGeometry.held(.done, pose: .still)
        }
        guard !reduceMotion else {
            return InkGeometry.listeningEyes(stretch: 0, gazeX: 0, blink: 0)
        }
        let time = CACurrentMediaTime()
        switch status {
        case .recording:
            let levels = driver.displayLevels
            let level = levels.isEmpty ? 0 : Double(levels.reduce(0, +)) / Double(levels.count)
            // The levels sit mostly under 0.5 for speech: doubled, a normal voice opens
            // the eyes about halfway and a loud one fully.
            return InkGeometry.listeningEyes(
                stretch: min(1, 2 * level),
                gazeX: 0,
                blink: InkGeometry.keyboardBlink(at: time)
            )
        case .transcribing, .processing:
            return InkGeometry.listeningEyes(stretch: 0, gazeX: InkGeometry.keyboardSweep(at: time), blink: 0)
        case .idle, .requested, .ready, .failed:
            return InkGeometry.listeningEyes(stretch: 0, gazeX: 0, blink: 0)
        }
    }
}
