import AVFoundation
import Foundation

/// Converts AVAudioPCMBuffer data to PCM16 (Int16) format and produces WAV files.
final class BuddyPCM16AudioConverter {

    // MARK: - Properties

    /// The target sample rate for output audio.
    let sampleRate: Double = 16000.0

    /// The number of channels (mono).
    let channels: UInt16 = 1

    /// Bits per sample.
    let bitsPerSample: UInt16 = 16

    /// Accumulated PCM16 audio data.
    private(set) var pcm16Data = Data()

    /// The content type for the WAV output.
    static let contentType = "audio/wav"

    // MARK: - Audio Conversion

    /// Append an AVAudioPCMBuffer, converting its float samples to PCM16 (Int16).
    /// - Parameter buffer: The audio buffer to convert and append.
    func appendAudioPCMBuffer(buffer: AVAudioPCMBuffer) {
        guard let floatChannelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelData = floatChannelData[0] // mono - use first channel

        var pcmBytes = Data(capacity: frameCount * MemoryLayout<Int16>.size)

        for i in 0..<frameCount {
            let sample = channelData[i]
            // Clamp to [-1.0, 1.0] and convert to Int16
            let clamped = max(-1.0, min(1.0, sample))
            var int16Sample = Int16(clamped * Float(Int16.max))
            pcmBytes.append(Data(bytes: &int16Sample, count: MemoryLayout<Int16>.size))
        }

        pcm16Data.append(pcmBytes)
    }

    // MARK: - WAV Generation

    /// Get the accumulated audio data as a complete WAV file.
    /// WAV header: RIFF, fmt chunk (PCM, mono, 16000Hz, 16-bit), data chunk.
    /// - Returns: Complete WAV file data ready for upload.
    func getWAVData() -> Data {
        var wavData = Data()

        let dataSize = UInt32(pcm16Data.count)
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let chunkSize = 36 + dataSize

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(littleEndianUInt32(chunkSize))

        // WAVE identifier
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(littleEndianUInt32(16))           // Sub-chunk size (16 for PCM)
        wavData.append(littleEndianUInt16(1))             // Audio format: 1 = PCM
        wavData.append(littleEndianUInt16(channels))      // Number of channels
        wavData.append(littleEndianUInt32(UInt32(sampleRate))) // Sample rate
        wavData.append(littleEndianUInt32(byteRate))      // Byte rate
        wavData.append(littleEndianUInt16(blockAlign))    // Block align
        wavData.append(littleEndianUInt16(bitsPerSample)) // Bits per sample

        // data sub-chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(littleEndianUInt32(dataSize))
        wavData.append(pcm16Data)

        return wavData
    }

    // MARK: - Reset

    /// Clear all buffered PCM16 data.
    func reset() {
        pcm16Data = Data()
    }

    /// Alias for reset.
    func clear() {
        reset()
    }

    // MARK: - Helpers

    private func littleEndianUInt32(_ value: UInt32) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: 4)
    }

    private func littleEndianUInt16(_ value: UInt16) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: 2)
    }
}
