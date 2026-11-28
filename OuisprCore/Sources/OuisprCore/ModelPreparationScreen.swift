// OuisprCore/Sources/OuisprCore/ModelPreparationScreen.swift
// What the model preparation screen draws for each phase: the opening phase, the one
// figure of progress and its milestones.
import Foundation

/// The phase the preparation screen is showing.
///
/// WHY IT IS HERE AND NOT PRIVATE TO THE VIEW (#708): the screen used to keep this enum to
/// itself, and the rule that decides the very first frame lived next to it, untested. That
/// rule is the whole of the "download that did not happen" defect: a screen opened for a
/// model already on disk drew the download phase at 0 % until the model manager caught up.
/// The rule has a right and a wrong answer, so it is held still by a test here, like the
/// countdown (`ModelPreparationCountdown`).
public enum ModelPreparationPhase: Equatable, Sendable {
    case downloading
    case compiling
    case loading
    case ready

    /// The phase to draw, given the phase the model's state maps to.
    ///
    /// WHY A MASK AT ALL: the parent raises the screen synchronously, and the work that
    /// moves the model out of its resting state starts on the next turn of the run loop
    /// (`ModelDownloadPage.startDownload` raises the screen, then starts a `Task`). Until
    /// a work phase has been seen, a resting `.ready` is "about to start", not "done",
    /// and drawing it as done would flash the completion state (commit f5ba7ab follow-up).
    ///
    /// WHY THE MASK DEPENDS ON THE DISK (#708, defect 1): it used to be `.downloading`
    /// whatever the disk held. For a model whose files are all present, the download phase
    /// is a lie even for one frame: no byte will move, and what comes next is the Core ML
    /// compile. The validated mock-up opens that case directly on the optimization frame
    /// (`B-optimisation`), so that is what the mask answers.
    ///
    /// - Parameters:
    ///   - raw: the phase the model's state maps to right now.
    ///   - hasSeenWorkPhase: whether the screen has observed real work yet.
    ///   - filesOnDisk: whether every file the model needs was on disk when the screen
    ///     opened.
    public static func displayed(raw: Self, hasSeenWorkPhase: Bool, filesOnDisk: Bool) -> Self {
        guard !hasSeenWorkPhase, raw == .ready else { return raw }
        return filesOnDisk ? .compiling : .downloading
    }
}

/// How far along the whole preparation is, as one number from 0 to 1: what the
/// percentage under the character says and what fills its eyes (lot 1.1, Alex's bench of
/// 27 Nov 2026, « Les yeux se remplissent », « Pourcentage seul »).
///
/// WHY TWO KINDS OF NUMBER IN ONE: the download reports a real fraction, the Core ML
/// compile and the load report none (#432, #533). The download, when there is one, fills
/// the first `downloadShare`; the preparation after it fills the rest from the time it
/// has run, on a curve that slows as it goes and stops at `preparationCeiling`. So the
/// figure always moves while something really runs, never goes back, and never says
/// 100 % before the model is really ready: only `.ready` does.
public enum ModelPreparationProgress {

    /// The part of the wait the download stands for, when there is one. A download is
    /// most of the first wait on every model in the catalogue but Turbo.
    public static let downloadShare = 0.9

    /// The highest figure the preparation's estimate reaches: 99 %.
    public static let preparationCeiling = 0.99

    /// The time constant of the estimate when the model's first preparation has never
    /// been measured: about 95 % of the way after 30 s.
    public static let unmeasuredTimeConstant = 10.0

    /// - Parameters:
    ///   - phase: the phase on screen.
    ///   - downloadFraction: the download's real progress, nil before its first tick.
    ///   - includesDownload: whether this preparation started with a download, that is,
    ///     the model's files were not all on disk when the screen opened.
    ///   - preparationElapsed: seconds since the compile or the load was first seen, nil
    ///     before.
    ///   - measuredSeconds: `ModelInfo.firstPreparationSeconds`, when known.
    public static func fraction(
        phase: ModelPreparationPhase,
        downloadFraction: Double?,
        includesDownload: Bool,
        preparationElapsed: Double?,
        measuredSeconds: Int?
    ) -> Double {
        let base = includesDownload ? downloadShare : 0
        switch phase {
        case .downloading:
            return downloadShare * clamp01(downloadFraction ?? 0)
        case .compiling, .loading:
            let elapsed = max(0, preparationElapsed ?? 0)
            // A third of the measured time: 95 % of the way when the measured time is up.
            let constant = measuredSeconds.map { max(1, Double($0) / 3) } ?? unmeasuredTimeConstant
            return base + (preparationCeiling - base) * (1 - exp(-elapsed / constant))
        case .ready:
            return 1
        }
    }

    /// The whole percent the screen prints: rounded down, so 99.6 % never reads 100 %.
    public static func percent(_ fraction: Double) -> Int {
        Int((clamp01(fraction) * 100).rounded(.down))
    }
}

/// The friendly line under the status, one per quarter (Alex, 27 Nov 2026: « un à 25,
/// 50, 75, 100 % »). Each stays until the next.
public enum ModelPreparationMilestone: Int, CaseIterable, Sendable {
    case quarter = 25
    case half = 50
    case threeQuarters = 75
    case done = 100

    /// The last milestone the figure has reached, nil under 25 %. `done` only for a ready
    /// model, whatever the figure says, since the estimate stops at 99 %.
    public static func reached(percent: Int, isReady: Bool) -> Self? {
        if isReady { return .done }
        return [.threeQuarters, .half, .quarter].first { percent >= $0.rawValue }
    }
}
