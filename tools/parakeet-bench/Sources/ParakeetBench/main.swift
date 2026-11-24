// tools/parakeet-bench/Sources/ParakeetBench/main.swift
//
// Transcribes every `<id>.wav` of a corpus directory with one Parakeet model, the way
// ParakeetEngine does in the app (fresh decoder state per clip, no `language:`, one chunk
// at a time), and writes one TSV row per clip: reference, hypothesis, WER, audio length
// and transcription time. References come from `corpus.tsv` (`id<TAB>text`).
//
// Usage: ParakeetBench --model v3|ultra --corpus <dir> --out <file.tsv> [--units ane|gpu]
import CoreML
import FluidAudio
import Foundation

struct Options {
    var model = AsrModelVersion.v3
    var modelName = "v3"
    var corpus = URL(fileURLWithPath: ".")
    var out = URL(fileURLWithPath: "results.tsv")
    var units: MLComputeUnits? = nil
}

func parse() -> Options {
    var o = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let a = args.next() {
        switch a {
        case "--model":
            o.modelName = args.next() ?? "v3"
            o.model = o.modelName == "ultra" ? .ultra : .v3
        case "--corpus": o.corpus = URL(fileURLWithPath: args.next() ?? ".")
        case "--out": o.out = URL(fileURLWithPath: args.next() ?? "results.tsv")
        case "--units": o.units = (args.next() == "gpu") ? .cpuAndGPU : .cpuAndNeuralEngine
        default: FileHandle.standardError.write("unknown argument \(a)\n".data(using: .utf8)!); exit(2)
        }
    }
    return o
}

/// Lowercase, no punctuation, apostrophes and hyphens as spaces, one space between words.
/// The same rule for reference and hypothesis, so it never favours one model.
func normalize(_ s: String) -> [String] {
    let folded = s.lowercased()
        .replacingOccurrences(of: "’", with: " ")
        .replacingOccurrences(of: "'", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "œ", with: "oe")
        .replacingOccurrences(of: "æ", with: "ae")
    // "22h30" → "22 h 30": digits and letters apart, so the numbers below can be spelled.
    var spaced = ""
    var lastWasDigit: Bool? = nil
    for ch in folded {
        let isDigit = ch.isNumber
        if let last = lastWasDigit, last != isDigit, ch.isLetter || isDigit { spaced.append(" ") }
        spaced.append(ch)
        lastWasDigit = (ch.isLetter || isDigit) ? isDigit : nil
    }
    let kept = spaced.unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? Character($0) : " " }
    let words = String(kept).split(separator: " ").map(String.init)
    // Writing a number in digits or in words is the same answer ("5 minutes" = "cinq minutes"),
    // and "h" after a number is "heures": a model is not penalised for its number format.
    var result: [String] = []
    for (i, w) in words.enumerated() {
        if let n = Int(w), let spelled = frenchNumber(n) {
            result += spelled
        } else if w == "h", i > 0, Int(words[i - 1]) != nil {
            result.append("heures")
        } else {
            result.append(w)
        }
    }
    return result
}

/// French words for 0...99, as `normalize` splits them ("vingt-deux" → ["vingt", "deux"]).
func frenchNumber(_ n: Int) -> [String]? {
    let units = ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix",
                 "onze", "douze", "treize", "quatorze", "quinze", "seize"]
    let tens = [2: "vingt", 3: "trente", 4: "quarante", 5: "cinquante", 6: "soixante"]
    switch n {
    case 0...16: return [units[n]]
    case 17...19: return ["dix", units[n - 10]]
    case 20...69:
        let t = tens[n / 10]!, u = n % 10
        return u == 0 ? [t] : u == 1 ? [t, "et", "un"] : [t] + frenchNumber(u)!
    case 70...79: return n == 71 ? ["soixante", "et", "onze"] : ["soixante"] + frenchNumber(n - 60)!
    case 80: return ["quatre", "vingts"]
    case 81...99: return ["quatre", "vingt"] + frenchNumber(n - 80)!
    default: return nil
    }
}

/// Word-level Levenshtein distance.
func editDistance(_ a: [String], _ b: [String]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    for i in 1...a.count {
        var cur = [i] + Array(repeating: 0, count: b.count)
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        prev = cur
    }
    return prev[b.count]
}

let o = parse()
let lines = try String(contentsOf: o.corpus.appendingPathComponent("corpus.tsv"), encoding: .utf8)
    .split(separator: "\n").map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
    .filter { $0.count == 2 }

let loadStart = Date()
let models = try await AsrModels.downloadAndLoad(version: o.model, encoderComputeUnits: o.units)
let manager = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1))
try await manager.loadModels(models)
let loadSeconds = Date().timeIntervalSince(loadStart)

// One untimed pass so the first measured clip does not pay for warm-up.
if let first = lines.first {
    let samples = try AudioConverter().resampleAudioFile(o.corpus.appendingPathComponent("\(first[0]).wav"))
    var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
    _ = try await manager.transcribe(samples, decoderState: &state)
}

var out = "id\tmodel\taudio_s\tlatency_ms\terrors\tref_words\treference\thypothesis\n"
var totalErrors = 0, totalWords = 0
var latencies: [Double] = []
for row in lines {
    let samples = try AudioConverter().resampleAudioFile(o.corpus.appendingPathComponent("\(row[0]).wav"))
    var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
    let start = Date()
    let result = try await manager.transcribe(samples, decoderState: &state)
    let ms = Date().timeIntervalSince(start) * 1000
    let ref = normalize(row[1]), hyp = normalize(result.text)
    let errors = editDistance(ref, hyp)
    totalErrors += errors; totalWords += ref.count; latencies.append(ms)
    let clean = result.text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    out += "\(row[0])\t\(o.modelName)\t\(String(format: "%.2f", Double(samples.count) / 16000))\t\(String(format: "%.0f", ms))\t\(errors)\t\(ref.count)\t\(row[1])\t\(clean)\n"
}
try out.write(to: o.out, atomically: true, encoding: .utf8)

let sorted = latencies.sorted()
func pct(_ p: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
print(String(format: "%@\tclips=%d\tWER=%.2f%%\tlatency_median=%.0fms\tp90=%.0fms\tload=%.1fs",
             o.modelName, lines.count, 100 * Double(totalErrors) / Double(max(totalWords, 1)),
             pct(0.5), pct(0.9), loadSeconds))
