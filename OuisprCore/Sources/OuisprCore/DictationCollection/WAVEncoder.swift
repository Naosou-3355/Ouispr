// OuisprCore/Sources/OuisprCore/DictationCollection/WAVEncoder.swift
// Float samples to a 16-bit PCM mono WAV file.
import Foundation

/// Encodes the recorder's Float samples as a standard WAV file.
///
/// WHY 16-bit PCM rather than Float32: every tool on the Mac side (afplay, ffmpeg,
/// Python's `wave`, the speech engines' own loaders) reads it without options, and
/// it halves the size. Speech at 16 kHz loses nothing measurable at 16 bits.
public enum WAVEncoder {

    /// The WAV bytes for `samples`, clamped to [-1, 1].
    public static func encode(samples: [Float], sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(samples.count) * UInt32(blockAlign)

        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))      // fmt chunk size
        data.appendLittleEndian(UInt16(1))       // PCM
        data.appendLittleEndian(channels)
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(dataSize)

        var pcm = [Int16]()
        pcm.reserveCapacity(samples.count)
        for sample in samples {
            let clamped = max(-1, min(1, sample.isFinite ? sample : 0))
            pcm.append(Int16(clamped * Float(Int16.max)).littleEndian)
        }
        pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
