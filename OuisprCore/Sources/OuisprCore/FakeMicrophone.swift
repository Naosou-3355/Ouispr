// OuisprCore/Sources/OuisprCore/FakeMicrophone.swift
// A recorded voice played in place of the microphone, for Debug simulator builds only.
#if DEBUG
import AVFoundation
#endif
import Foundation

/// The engine's two calls into the fake microphone. Empty functions outside a Debug
/// simulator build, so a Release build or a device carries no fake-microphone code and
/// behaves exactly as before.
///
/// WHY here and not as `#if` blocks in `UnifiedAudioEngine`: that file sits at the
/// lint's length limit, and two plain calls keep the engine readable.
public enum FakeMicrophoneInput {
    #if DEBUG && targetEnvironment(simulator)
    /// Read once, at the first audio buffer: the setting is a launch-time one.
    private static let active = FakeMicrophone.configured()
    #endif

    /// Replaces `samples` with the next stretch of the recording, when one is set.
    @inline(__always)
    public static func substitute(_ samples: inout [Float]) {
        #if DEBUG && targetEnvironment(simulator)
        if let active {
            samples = active.next(count: samples.count)
        }
        #endif
    }

    /// Starts the recording again from its first sample, when one is set.
    @inline(__always)
    public static func rewind() {
        #if DEBUG && targetEnvironment(simulator)
        active?.rewind()
        #endif
    }
}

#if DEBUG

/// A recording that stands in for the microphone, so a dictation can be tried where
/// there is no microphone signal.
///
/// WHY it exists: since Xcode 27 there is no Simulator app to ask macOS for the
/// microphone, and the simulator receives exact silence (measured 22 Nov 2026: every
/// waveform snapshot at 0.000 while a sentence was spoken next to the Mac). The sphere
/// could not react and a dictation always ended in "no speech detected".
///
/// WHY it swaps samples rather than feeding a fake engine: the app keeps its real
/// AVAudioEngine and its real tap, and only the converted 16 kHz samples are replaced,
/// buffer by buffer. Everything downstream (the levels that drive the sphere, the
/// buffer the model transcribes, the elapsed time) runs exactly as with a voice, at the
/// tap's own pace, which is real time.
///
/// Compiled in Debug only; the app further limits it to the simulator. Without the
/// setting below it is never created and nothing changes.
public final class FakeMicrophone: @unchecked Sendable {
    /// Environment variable holding the recording's path. From the host, pass it as
    /// `SIMCTL_CHILD_OUISPR_FAKE_MIC=/path/voice.wav xcrun simctl launch …`.
    public static let environmentKey = "OUISPR_FAKE_MIC"

    /// The same setting as a user default, which survives a launch from the home
    /// screen (an environment variable only reaches a `simctl launch`).
    public static let defaultsKey = "OuisprFakeMic"

    /// The recording, 16 kHz mono Float32: the format the engine converts to.
    public let samples: [Float]

    // WHY a lock: `next` runs on the audio thread, `rewind` on the main thread.
    private let lock = NSLock()
    private var position = 0

    public init(samples: [Float]) {
        self.samples = samples
    }

    /// Reads any file AVAudioFile can open and converts it to 16 kHz mono.
    /// Nil when the file is missing, unreadable or empty.
    public convenience init?(contentsOf url: URL) {
        guard let samples = Self.load(url), !samples.isEmpty else { return nil }
        self.init(samples: samples)
    }

    /// The fake microphone the settings ask for, or nil when none is set.
    /// The environment wins over the user default.
    public static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> FakeMicrophone? {
        let path = environment[environmentKey] ?? defaults.string(forKey: defaultsKey)
        guard let path, !path.isEmpty else { return nil }
        return FakeMicrophone(contentsOf: URL(fileURLWithPath: path))
    }

    /// Back to the start: each dictation hears the recording from its first word.
    public func rewind() {
        lock.lock()
        position = 0
        lock.unlock()
    }

    /// The next `count` samples of the recording. Once it has played, silence: the
    /// dictation then ends the way a quiet room ends it, when the user stops it.
    public func next(count: Int) -> [Float] {
        guard count > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let start = min(position, samples.count)
        let end = min(start + count, samples.count)
        position = start + count
        var chunk = Array(samples[start..<end])
        if chunk.count < count {
            chunk.append(contentsOf: repeatElement(0, count: count - chunk.count))
        }
        return chunk
    }

    private static func load(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ),
              (try? file.read(into: input)) != nil
        else { return nil }

        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            // The whole file in one go, then the end of the stream so the converter
            // flushes what it holds.
            if delivered {
                inputStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let channel = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
    }
}
#endif
