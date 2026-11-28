// OuisprCore/Sources/OuisprCore/Design/InkCharacterDriver.swift
// The ink character's clock: springs, gaze, blinks, and the passages between moods.
import Foundation

/// A damped spring stepped by elapsed time. `response` is the period in seconds,
/// `damping` 1 for no overshoot (Apple's model, WWDC23 "Animate with springs").
struct InkSpring {
    var value: Double
    var target: Double
    private var velocity = 0.0
    private let stiffness: Double
    private let friction: Double

    init(_ value: Double, response: Double, damping: Double) {
        self.value = value
        target = value
        stiffness = pow(2 * .pi / response, 2)
        friction = 4 * .pi * damping / response
    }

    mutating func step(_ dt: Double) {
        // Fixed 4 ms substeps keep a stiff spring stable on a long frame.
        let count = max(1, Int((dt / 0.004).rounded(.up)))
        let h = dt / Double(count)
        for _ in 0..<count {
            velocity += (-stiffness * (value - target) - friction * velocity) * h
            value += velocity * h
        }
    }

    mutating func kick(_ dv: Double) { velocity += dv }

    mutating func settle() {
        value = target
        velocity = 0
    }
}

/// Moves the ink character from mood to mood and hands out one `InkFrame` per frame.
///
/// A passage, once started, always plays through: the ink never jumps. When the mood
/// changes in the middle of one (a dictation cancelled while the eyes are opening, a
/// transcription that ends before the wave has calmed), the running passage speeds up
/// to 2.5 times, smoothly, then the next one leads to the new mood. A mood two steps
/// away goes through the one between, the way it would have gone anyway.
///
/// A reference type on purpose: Home and the recording screen show the same
/// character, and share one driver so the one that appears carries on its motion.
public final class InkCharacterDriver {
    public static let shared = InkCharacterDriver()

    private struct Passage {
        let from: ParticleSphereMood
        let to: ParticleSphereMood
        let duration: Double
        var elapsed = 0.0
        var rate: Double
        let gazeX: Double
        let gazeY: Double
    }

    /// The mood the ink has settled in (or is leaving, while a passage runs).
    public private(set) var settled: ParticleSphereMood = .resting
    private var passage: Passage?

    private var levels = InkGeometry.baseHeights.map { InkSpring($0 / 42 * 0.5, response: 0.26, damping: 0.8) }
    private var gazeX = InkSpring(0, response: 0.45, damping: 0.9)
    private var gazeY = InkSpring(0, response: 0.45, damping: 0.9)
    private var voice = 0.0
    private var slowVoice = 0.0
    private var onsetCooldown = 0.0
    private var history: [(time: Double, level: Double)] = []
    private var phase = 0.0
    private var clock = 0.0
    private var nextLook = 1.0
    private var nextBlink = 2.2
    private var blinkTime = -1.0
    private var random = InkRandom(seed: 7)
    private var lastTime: Double?
    /// When a screen last asked for a mood other than rest; see `frame`.
    private var lastActiveRequest = -Double.infinity
    private var target: ParticleSphereMood = .resting

    public init() {}

    /// A driver already settled in `mood`, with no passage to play first: the keyboard's
    /// listening screen starts on the wave, its own mic having just turned into it (lot 1.8).
    public init(settledIn mood: ParticleSphereMood) {
        settled = mood
        target = mood
        snap()
    }

    /// True while a passage is playing.
    public var isMoving: Bool { passage != nil }

    /// Advances to `time` (seconds, any monotonic origin) and returns what to draw.
    ///
    /// - Parameters:
    ///   - advancing: false for a paused view, drawn once without moving the clock.
    ///   - reduceMotion: no passages and no loops: the ink is shown in each mood's
    ///     held shape, the wave at a fixed height (Apple HIG, Motion: offer a calmer
    ///     alternative rather than none).
    public func frame(
        at time: Double,
        mood: ParticleSphereMood,
        voiceLevel: Double,
        reduceMotion: Bool,
        advancing: Bool = true
    ) -> InkFrame {
        // A paused view shows its mood's held shape, open eyes looking ahead, never the
        // frame it stopped on: frozen mid-blink or mid-passage, the same resting face read
        // as two dashes or two dots depending on the screen (audit of 26 Nov 2026, n°21).
        // Nothing is mutated, not even the clock or the target: the shared driver may be
        // running on another screen, whose next step must not lose its time.
        guard advancing else { return InkGeometry.held(mood, pose: pose) }

        // Home and the recording screen can both draw for a moment during the sphere's
        // flight back home, Home asking for rest while the recording screen still
        // shows the result. The screen that shows a dictation wins: a request for rest
        // is ignored while another mood was asked for in the last tenth of a second.
        if mood != .resting { lastActiveRequest = time }
        if mood != .resting || time - lastActiveRequest > 0.1 { target = mood }

        // A long gap (paused, backgrounded) resumes without a jump.
        let dt = lastTime.map { min(max(time - $0, 0), 1.0 / 15.0) } ?? 0
        lastTime = time
        if dt > 0 { step(dt, reduceMotion: reduceMotion, voiceLevel: voiceLevel) }
        return render()
    }

    // MARK: - Stepping

    private func step(_ dt: Double, reduceMotion: Bool, voiceLevel: Double) {
        clock += dt
        let listening = target == .listening
        let input = listening ? clamp01(voiceLevel) : 0
        voice += min(1, (input > voice ? 18 : 6) * dt) * (input - voice)
        let v = clamp01(voice)
        slowVoice += (v - slowVoice) * (1 - exp(-dt * 5))
        onsetCooldown -= dt
        var onset = 0.0
        if listening, v - slowVoice > 0.05, onsetCooldown <= 0 {
            onset = min(1, (v - slowVoice) * 7)
            onsetCooldown = 0.15
        }

        if reduceMotion {
            snap()
        } else {
            advancePassage(dt)
        }
        // The glide a little livelier with the voice (26 Nov 2026, « onduler un peu plus »).
        phase += reduceMotion ? 0 : dt * (listening ? 0.4 + 1.3 * v : 0.2)

        // Each ondulation keeps its own level, slightly behind the others, as in « Le
        // logo qui parle ».
        history.append((clock, v))
        while history.count > 2 && history[0].time < clock - 0.2 { history.removeFirst() }
        for k in 0..<3 {
            let base = InkGeometry.baseHeights[k] / 42
            let lag = [0.09, 0, 0.05][k]
            let wobble = 0.86 + 0.14 * sin(clock * [5.1, 6.3, 4.4][k] + Double(k) * 1.9)
            // Alex's 2B (25 Nov 2026): the voice is amplified and its peaks softened, so
            // the wave lies almost flat in silence and plainly rises with speech.
            let voiced = pow(clamp01(1.5 * past(lag)), 0.75)
            let level = reduceMotion ? base * 0.8 : base * (0.35 + 1.35 * voiced * wobble)
            levels[k].target = listening ? level : base * 0.5
            if onset > 0, k == 1, !reduceMotion { levels[k].kick(1.2 * onset) }
            if reduceMotion { levels[k].settle() } else { levels[k].step(dt) }
        }

        // At rest the gaze wanders and the eyes blink; elsewhere the gaze is centred.
        let atRest = settled == .resting && passage == nil
        if atRest, !reduceMotion {
            nextLook -= dt
            if nextLook <= 0 {
                gazeX.target = (random.next() - 0.5) * 0.5
                gazeY.target = (random.next() - 0.5) * 0.25
                nextLook = 1.4 + random.next() * 1.4
            }
            nextBlink -= dt
            if nextBlink <= 0 {
                blinkTime = 0
                nextBlink = 2.6 + random.next() * 2
            }
        } else {
            gazeX.target = 0
            gazeY.target = 0
            // Back at rest, the eyes stay open a moment before the first blink.
            nextBlink = max(nextBlink, 1.2)
        }
        if reduceMotion {
            gazeX.settle(); gazeY.settle()
            blinkTime = -1
        } else {
            gazeX.step(dt); gazeY.step(dt)
        }
        if blinkTime >= 0 {
            blinkTime += dt
            if blinkTime > 0.16 { blinkTime = -1 }
        }
    }

    private func past(_ delay: Double) -> Double {
        for entry in history.reversed() where entry.time <= clock - delay { return entry.level }
        return history.first?.level ?? 0
    }

    private func advancePassage(_ dt: Double) {
        if var running = passage {
            // A passage that no longer leads to the wanted mood hurries, without a jump.
            let goal = running.to == target ? 1.0 : 2.5
            running.rate += (goal - running.rate) * (1 - exp(-dt * 10))
            running.elapsed += dt * running.rate
            if running.elapsed >= running.duration {
                settled = running.to
                passage = nil
            } else {
                passage = running
            }
        }
        guard passage == nil, let next = Self.next(from: settled, toward: target) else { return }
        passage = Passage(
            from: settled,
            to: next,
            duration: Self.duration(from: settled, to: next),
            rate: next == target ? 1 : 2.5,
            gazeX: gazeX.value,
            gazeY: gazeY.value
        )
    }

    private func snap() {
        settled = target
        passage = nil
        gazeX.target = 0; gazeY.target = 0
        gazeX.settle(); gazeY.settle()
        blinkTime = -1
        for k in 0..<3 {
            let base = InkGeometry.baseHeights[k] / 42
            levels[k].target = target == .listening ? base * 0.8 : base * 0.5
            levels[k].settle()
        }
    }

    /// The next mood on the way from `from` to `target`: the dictation's own order
    /// (rest, listening, working, done, rest), with two ways back to rest for a
    /// dictation cancelled or failed while listening or working.
    static func next(from: ParticleSphereMood, toward target: ParticleSphereMood) -> ParticleSphereMood? {
        guard from != target else { return nil }
        switch from {
        case .resting: return .listening
        case .listening: return target == .resting ? .resting : .working
        case .working: return target == .done ? .done : target == .resting ? .resting : .listening
        case .done: return .resting
        }
    }

    /// The passages' lengths, from the benches: the arch 0.9 s (Alex's compromise),
    /// the calm 0.7 s, the drop 0.8 s, the wake 0.55 s. The ways back from a cancelled
    /// dictation take 0.7 s: the system answering, quicker than the user's own start.
    static func duration(from: ParticleSphereMood, to: ParticleSphereMood) -> Double {
        switch (from, to) {
        case (.resting, .listening): return 0.9
        case (.working, .done): return InkGeometry.dropDuration
        case (.done, .resting): return 0.55
        default: return 0.7
        }
    }

    // MARK: - Drawing

    private var pose: InkPose { InkPose(levels: levels.map(\.value), phase: phase, clock: clock) }

    private func render() -> InkFrame {
        let pose = pose
        guard let running = passage else {
            let blink = blinkTime >= 0 ? sin(.pi * blinkTime / 0.16) : 0
            return InkGeometry.held(settled, pose: pose, gazeX: gazeX.value, gazeY: gazeY.value, blink: blink)
        }
        let tau = clamp01(running.elapsed / running.duration)
        switch (running.from, running.to) {
        case (.resting, .listening):
            return InkGeometry.arch(tau, gazeX: running.gazeX, gazeY: running.gazeY) { InkGeometry.wave($0, pose) }
        case (.listening, .resting):
            return InkGeometry.arch(1 - tau, gazeX: 0, gazeY: 0) { InkGeometry.wave($0, pose) }
        case (.working, .resting):
            return InkGeometry.arch(1 - tau, gazeX: 0, gazeY: 0, lineHalf: 0.6 * InkGeometry.halfLength) {
                InkGeometry.bump($0, pose)
            }
        case (.listening, .working):
            return InkGeometry.calm(tau, pose: pose)
        case (.working, .listening):
            return InkGeometry.calm(1 - tau, pose: pose)
        case (.working, .done):
            return InkGeometry.drop(tau, pose: pose)
        case (.done, .resting):
            return InkGeometry.wake(tau)
        default:
            return InkGeometry.held(running.to, pose: pose)
        }
    }
}

/// A small seeded generator, so the gaze wanders the same way on every run.
struct InkRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
