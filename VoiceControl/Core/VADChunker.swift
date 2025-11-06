import Foundation
import os.log

private let logger = os.Logger(subsystem: "com.yourteam.VoiceControl", category: "VADChunker")

class VADChunker {
    // Dependencies
    private let vadDetector = VADSilenceDetector()
    
    // Chunk emission callback
    var onChunkReady: ((Data) -> Void)?
    
    init() {
        logger.info("VADChunker initialized with FluidAudio VAD")

        // Setup VAD detector callback
        vadDetector.onChunkReady = { [weak self] chunkData in
            guard let self = self else { return }

            logger.info("VADChunker received chunk from FluidAudio VAD: \(chunkData.count) bytes")

            // Forward the chunk to our callback
            self.onChunkReady?(chunkData)
        }
    }
    
    func processAudioBuffer(_ buffer: [Float]) {
        print("📦 VADChunker: Processing buffer with \(buffer.count) samples")

        // Convert Float array to Data
        let audioData = buffer.withUnsafeBufferPointer { pointer in
            Data(buffer: pointer)
        }

        print("📦 VADChunker: Converted to \(audioData.count) bytes, sending to VAD detector")

        // Process with VAD detector
        // The VADSilenceDetector will handle all the voice detection logic
        // and call our callback when a complete speech segment is detected
        _ = vadDetector.processAudioData(audioData)
    }
    
    func reset() {
        vadDetector.reset()
        logger.info("VADChunker fully reset")
    }
}