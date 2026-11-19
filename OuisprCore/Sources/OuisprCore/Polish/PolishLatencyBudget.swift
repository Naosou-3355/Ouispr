// OuisprCore/Sources/OuisprCore/Polish/PolishLatencyBudget.swift
// How long the user waits for the model after they stop speaking.
import Foundation

/// The free polish's wait after the dictation stops, by length.
///
/// WHY: the model's time is the user's wait, and its value does not grow with it — a
/// 492-word dictation took 16.9 s and changed 3 words (alex01, 2026-11-19). Past the
/// budget the deterministic floor is inserted: hesitations removed, verbal
/// punctuation, typography, the email layout. Agreed with Alex on 2026-11-19:
///
/// - under `shortWords` words: no wait, the rules only — unless the dictation holds
///   something only the model can fix (a spoken self-correction, an announcement
///   that takes `:`), which gets the message budget;
/// - a message: `messageSeconds`;
/// - growing linearly to `longSeconds` at `longWords` words, and no further.
///
/// The keyboard's watchdog (`PolishTimeBudget`) is unchanged: it guards a call that
/// hangs, this decides how long a working call is worth waiting for. Smart Modes
/// have no budget: the user armed them and waits for what they asked.
public enum PolishLatencyBudget {

    /// Off until the model can run while the user is still speaking (#2 of the
    /// 2026-11-19 plan): measured on an M3 Max, a short dictation already takes
    /// 0.95 s in the model, so a 0.5 s budget after the stop hands nearly every
    /// dictation to the floor. The harness turns it on with `--budget` to measure it.
    nonisolated(unsafe) public static var isEnabled = false

    public static let shortWords = 15
    public static let messageSeconds: TimeInterval = 0.5
    public static let longSeconds: TimeInterval = 1.5
    public static let longWords = 150

    /// The budget the app applies: nil (no budget) while `isEnabled` is off.
    public static func appliedSeconds(for preprocessed: String, language: SupportedLanguage?) -> TimeInterval? {
        isEnabled ? seconds(for: preprocessed, language: language) : nil
    }

    public static func seconds(for preprocessed: String, language: SupportedLanguage?) -> TimeInterval {
        let words = preprocessed.split(whereSeparator: \.isWhitespace).count
        if words < shortWords {
            return needsModel(preprocessed, language: language) ? messageSeconds : 0
        }
        let span = Double(longWords - shortWords)
        let progress = min(1, Double(words - shortWords) / span)
        return messageSeconds + (longSeconds - messageSeconds) * progress
    }

    /// A short dictation the rules cannot finish: a self-correction said aloud, or an
    /// announcement the model closes with `:`.
    static func needsModel(_ text: String, language: SupportedLanguage?) -> Bool {
        guard let language, let cues = cuePatterns[language] else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return cues.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    static let cuePatterns: [SupportedLanguage: [NSRegularExpression]] = {
        let french = [
            // rule 10
            #"\b(non|pardon|enfin|plutôt|attends|trompée?)\b"#,
            #"\b(en fait|je veux dire)\b"#,
            // contextual colon
            #"\b(truc|chose|histoire)\s+(de\s+(fou|dingue|ouf)|incroyable)\b"#,
            #"\b(devine|tu\s+sais|sais-tu)\s+quoi\b"#,
            #"\bnouvelle\b"#,
            #"\bvoilà\s+ce\s+(qu['’]|que\b|qui\b)"#,
            #"\b(choses|trucs)\b"#,
            #"\bm['’](a|ont)\s+(répondu|annoncé|avoué|raconté|expliqué)\b"#,
            #"\brappel\b"#,
            #"\bsimple\b"#
        ]
        let english = [
            #"\b(no|sorry|actually|rather|wait)\b"#,
            #"\b(i mean|scratch that)\b"#
        ]
        func compile(_ list: [String]) -> [NSRegularExpression] {
            list.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        }
        return [.french: compile(french), .english: compile(english)]
    }()
}

extension PolishPipeline {

    /// `transform`, cut off at `budget` seconds. Past it the call is cancelled and
    /// the result is `overTimeBudget`, which `resolvedOutput` turns into the floor.
    /// A budget of zero never calls the engine.
    public static func transform(preprocessed: String,
                                 engine: PolishEngineProtocol,
                                 job: PolishJob,
                                 gate: PolishAvailabilityGate,
                                 budget: TimeInterval?) async -> Result {
        guard let budget else {
            return await transform(preprocessed: preprocessed, engine: engine, job: job, gate: gate)
        }
        guard budget > 0 else {
            return Result(engineOutput: nil, outcome: .overTimeBudget, engineMs: 0, postprocessMs: 0)
        }
        // Not a task group: a group waits for every child, so it would wait for the
        // model it means to stop. The first of the two to finish resumes the caller;
        // the model's task is cancelled and left to wind down on its own.
        let race = BudgetRace()
        return await withCheckedContinuation { continuation in
            let work = Task {
                let result = await transform(preprocessed: preprocessed, engine: engine, job: job, gate: gate)
                await race.finish(result, continuation)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                let over = Result(engineOutput: nil, outcome: .overTimeBudget,
                                  engineMs: Int(budget * 1000), postprocessMs: 0)
                if await race.finish(over, continuation) { work.cancel() }
            }
        }
    }
}

/// Resumes a continuation once, with whichever result arrives first.
private actor BudgetRace {
    private var done = false

    @discardableResult
    func finish(_ result: PolishPipeline.Result, _ continuation: CheckedContinuation<PolishPipeline.Result, Never>) -> Bool {
        guard !done else { return false }
        done = true
        continuation.resume(returning: result)
        return true
    }
}
