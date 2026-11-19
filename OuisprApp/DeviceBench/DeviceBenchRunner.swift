// OuisprApp/DeviceBench/DeviceBenchRunner.swift
//
// On-device latency and quality bench: the Mac bench (`tools/device-bench`), run on
// the iPhone itself. Every clip goes through the app's own Parakeet v3 engine, then
// through the polish pipeline on the iPhone's Apple Intelligence model, and one row
// per clip is appended to a TSV in the app's Documents, which the Mac copies back
// with `devicectl`.
//
// WHY inside OuisprApp rather than a separate bench app: a free Apple ID allows ten
// App IDs a week and seven are already taken, so the bench cannot have a bundle id of
// its own. It is dormant unless the app is launched with `--device-bench`, which only
// `devicectl device process launch` does; a user never reaches it.
//
// WHY the polish path below restates `polish-harness`'s `runOnce` instead of calling
// `PolishService`: the service reads the user's settings (toggle, language policy,
// armed Smart Mode), and the bench must run the same fixed path the Mac numbers were
// taken on — French, Parakeet, free polish, prewarm then a 2 s "recording" pause.
import Foundation
import UIKit
import OuisprCore
import FluidAudio
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class DeviceBenchRunner {

    /// The launch argument that starts the bench.
    static let launchArgument = "--device-bench"
    /// Added to it, throws the previous results away instead of resuming after them.
    static let freshArgument = "--device-bench-fresh"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    private static var shared: DeviceBenchRunner?

    /// Start once per process. Called from `didFinishLaunching`.
    static func startIfRequested() {
        guard isRequested, shared == nil else { return }
        let runner = DeviceBenchRunner()
        shared = runner
        Task { await runner.run() }
    }

    // MARK: - Files

    /// `Documents/device-bench/` — `corpus/` is copied in by the Mac, `out/` is copied back.
    private let root: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("device-bench", isDirectory: true)
    }()
    private var corpusDirectory: URL { root.appendingPathComponent("corpus", isDirectory: true) }
    private var outDirectory: URL { root.appendingPathComponent("out", isDirectory: true) }
    private var resultsFile: URL { outDirectory.appendingPathComponent("results.tsv") }

    private static let header = [
        "id", "audio_s", "asr_ms", "polish_ms", "total_ms", "outcome", "check",
        "thermal", "hypothesis", "polished", "engine_out"
    ].joined(separator: "\t") + "\n"

    /// `phase.txt` is one word the Mac polls: loading, running, done, failed.
    private func writePhase(_ phase: String, detail: String = "") {
        let text = detail.isEmpty ? phase + "\n" : phase + "\n" + detail + "\n"
        try? text.write(to: outDirectory.appendingPathComponent("phase.txt"), atomically: true, encoding: .utf8)
    }

    private func writeProgress(_ done: Int, of total: Int) {
        let line = "\(done)/\(total) \(ISO8601DateFormatter().string(from: Date()))\n"
        try? line.write(to: outDirectory.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8)
    }

    private func append(_ row: String) {
        guard let data = row.data(using: .utf8), let handle = try? FileHandle(forWritingTo: resultsFile) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    // MARK: - Run

    private func run() async {
        if ProcessInfo.processInfo.arguments.contains(Self.freshArgument) {
            try? FileManager.default.removeItem(at: outDirectory)
        }
        try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        // An hour of work with nobody touching the screen: keep it from locking, which
        // would background the app and change what is being measured.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        writePhase("loading")

        do {
            try await runBench()
        } catch {
            writePhase("failed", detail: String(describing: error))
        }
    }

    private struct BenchError: Error, CustomStringConvertible {
        let description: String
    }

    private func runBench() async throws {
        guard #available(iOS 26.0, *) else {
            throw BenchError(description: "Apple Intelligence needs iOS 26")
        }
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            throw BenchError(description: "Apple Intelligence unavailable: \(SystemLanguageModel.default.availability)")
        }
        #endif

        let rows = try String(contentsOf: corpusDirectory.appendingPathComponent("corpus.tsv"), encoding: .utf8)
            .split(separator: "\n")
            .map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
            .filter { $0.count == 2 }
        guard !rows.isEmpty else { throw BenchError(description: "empty corpus") }

        // Resume after a crash or a relaunch: ids already written are not run again.
        var doneIDs = Set<String>()
        if let existing = try? String(contentsOf: resultsFile, encoding: .utf8) {
            for line in existing.split(separator: "\n").dropFirst() {
                if let id = line.split(separator: "\t").first { doneIDs.insert(String(id)) }
            }
        } else {
            try Self.header.write(to: resultsFile, atomically: true, encoding: .utf8)
        }

        // The dictation coordinator may be loading its own engine at launch; two Core ML
        // compilations at once on the Neural Engine crash (see ParakeetEngine). Let it finish.
        try await Task.sleep(for: .seconds(20))

        let stt = ParakeetEngine()
        try await stt.prepare(modelIdentifier: "parakeet-tdt-0.6b-v3")
        try await stt.runWarmInference()

        let polish = AppleFoundationModelsPolishEngine()
        writePhase("running")

        var done = doneIDs.count
        writeProgress(done, of: rows.count)
        for row in rows where !doneIDs.contains(row[0]) {
            let id = row[0]
            let samples = try AudioConverter().resampleAudioFile(corpusDirectory.appendingPathComponent("\(id).wav"))

            let asrStart = Date()
            let hypothesis: String
            do {
                hypothesis = try await stt.transcribe(audioSamples: samples, language: nil).text
            } catch {
                hypothesis = ""
            }
            let asrMs = Date().timeIntervalSince(asrStart) * 1000

            let result = await polishOnce(hypothesis, engine: polish)
            let thermal = Self.thermalName(ProcessInfo.processInfo.thermalState)
            let fields = [
                id,
                String(format: "%.2f", Double(samples.count) / 16_000),
                String(format: "%.0f", asrMs),
                "\(result.ms)",
                String(format: "%.0f", asrMs + Double(result.ms)),
                result.outcome,
                result.check,
                thermal,
                Self.clean(hypothesis),
                Self.clean(result.text),
                Self.clean(result.engineOut ?? "")
            ]
            append(fields.joined(separator: "\t") + "\n")
            done += 1
            writeProgress(done, of: rows.count)
        }
        writePhase("done")
    }

    // MARK: - Polish (mirrors polish-harness `runOnce`, per-language path)

    private struct PolishOutcome {
        let text: String
        let outcome: String
        let ms: Int
        let check: String
        let engineOut: String?
    }

    @available(iOS 26.0, *)
    private func polishOnce(_ raw: String, engine: any PolishEngineProtocol) async -> PolishOutcome {
        let target = SupportedLanguage.french
        let preprocessed = VerbalPunctuationPrepass.apply(raw, language: target)
        let mix = PolishLanguageMix.measure(raw)
        let detected = mix.dominantSupportedLanguage
        if PolishGatePolicy.skipsForGibberish(hasDetectedLanguage: detected != nil, task: .natural) {
            let floor = PolishPostpass.decodeFromEngine(preprocessed, language: target)
            return PolishOutcome(text: floor, outcome: "skipped", ms: 0, check: "", engineOut: nil)
        }
        if PolishGatePolicy.skipsForCleanInput(
            preprocessed, language: detected == target ? target : nil,
            isMixed: mix.isMixed, task: .natural
        ) {
            let floor = PolishEmailLayout.apply(
                PolishPostpass.decodeFromEngine(preprocessed, language: target), language: target
            )
            return PolishOutcome(text: floor, outcome: "skippedClean", ms: 0, check: "", engineOut: nil)
        }
        let job = PolishJob(
            task: .polish(PolishPipeline.mode(sttEngine: .parakeet, detected: detected ?? target, target: target)),
            promptLanguage: target,
            languageAgnosticPath: false,
            inputLanguageCodes: mix.countedCodes,
            transcriptLanguageCode: PolishJob.transcriptLanguageCode(mode: .explicit(target), detectedCode: mix.dominantCode)
        )
        // Warm the session as the app does when recording starts, then wait the 2 s the
        // Mac bench waits: the timing is the one a user sees after they stop speaking.
        await engine.prewarm(task: job.task, targetLanguage: job.promptLanguage)
        try? await Task.sleep(for: .seconds(2))
        let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, job: job)
        let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, job: job) ?? ""
        return PolishOutcome(text: final, outcome: r.outcome.rawValue, ms: r.engineMs,
                             check: r.rejectedCheck?.rawValue ?? "", engineOut: r.engineOutput)
    }

    // MARK: - Helpers

    /// One TSV field: breaks are kept visible as ⏎ so the scorer can count them.
    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "⏎")
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
