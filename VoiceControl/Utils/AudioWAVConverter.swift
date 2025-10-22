import Foundation

/// Utility class for converting raw PCM audio data to WAV format
class AudioWAVConverter {
    /// Converts raw PCM float audio data to a properly formatted WAV file
    /// that AVAudioPlayer can play back
    ///
    /// - Parameters:
    ///   - audioData: Raw PCM float data (32-bit float samples)
    ///   - sampleRate: Sample rate in Hz (default: 16000)
    /// - Returns: WAV formatted audio data with proper RIFF header
    static func convertToWAV(audioData: Data, sampleRate: Double = 16000) -> Data {
        let pcmData = audioData
        let sampleRate: Int32 = Int32(sampleRate)
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 32
        let byteRate = sampleRate * Int32(numChannels) * Int32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = Int32(pcmData.count)

        var header = Data()

        // RIFF chunk descriptor
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: Int32(36 + dataSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)

        // fmt sub-chunk
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: Int16(3).littleEndian) { Data($0) })  // IEEE Float (format code 3)
        header.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })

        // data sub-chunk
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        return header + pcmData
    }
}
