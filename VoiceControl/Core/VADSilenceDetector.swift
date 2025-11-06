import Foundation
import os.log
import FluidAudio

private let logger = os.Logger(subsystem: "com.yourteam.VoiceControl", category: "VADSilenceDetector")

class VADSilenceDetector: NSObject {
    enum DetectionState {
        case idle
        case speechDetected
        case trailingSilence
    }

    enum DetectionResult {
        case `continue`
        case chunkReady
    }

    private(set) var state: DetectionState = .idle

    private var vadManager: VadManager?
    private var streamState: VadStreamState?
    private var currentAudioChunk: Data = Data()
    private var isProcessingVoice = false

    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private var silenceStartTime: Date?
    private var speechStartTime: Date?

    // Callback for when chunk is ready
    var onChunkReady: ((Data) -> Void)?

    // For debugging
    private(set) var currentSpeechThreshold: Float = 0.02  // Not used with VAD, kept for compatibility
    private(set) var currentSilenceThreshold: Float = 0.01  // Not used with VAD, kept for compatibility

    override init() {
        super.init()

        print("🎙️ VAD: Initializing VADSilenceDetector")

        // Initialize FluidAudio VadManager asynchronously
        Task {
            do {
                print("🎙️ VAD: Creating VadManager...")
                // Create VAD config with threshold similar to previous setup (0.7)
                let config = VadConfig(defaultThreshold: 0.7)
                self.vadManager = try await VadManager(config: config)

                // Create streaming state
                self.streamState = await self.vadManager?.makeStreamState()

                print("✅ VAD: VADSilenceDetector initialized with FluidAudio Silero VAD")
                logger.info("VADSilenceDetector initialized with FluidAudio Silero VAD")
            } catch {
                print("❌ VAD: Failed to initialize FluidAudio VadManager: \(error.localizedDescription)")
                logger.error("Failed to initialize FluidAudio VadManager: \(error.localizedDescription)")
            }
        }
    }

    func reset() {
        state = .idle
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        silenceStartTime = nil
        speechStartTime = nil
        currentAudioChunk = Data()
        isProcessingVoice = false

        // Reset streaming state
        Task {
            if let manager = vadManager {
                streamState = await manager.makeStreamState()
            }
        }

        logger.info("VADSilenceDetector reset")
    }

    func process(rms: Float, timestamp: Date) -> DetectionResult {
        // This method is for compatibility with DynamicSilenceDetector interface
        // VAD doesn't use RMS, so we just return continue
        return .continue
    }

    func processAudioData(_ audioData: Data) -> DetectionResult {
        print("🔍 VADDetector: Received \(audioData.count) bytes")

        // Convert Data to Float array
        let floatArray = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }

        print("🔍 VADDetector: Converted to \(floatArray.count) float samples")

        // ALWAYS accumulate audio regardless of state to ensure no audio is lost
        currentAudioChunk.append(audioData)
        print("🔍 VADDetector: Accumulated chunk now \(currentAudioChunk.count) bytes, state: \(state)")

        // Process with FluidAudio VAD asynchronously
        Task {
            guard let manager = vadManager, var state = streamState else {
                print("⚠️ VAD: VadManager or stream state not initialized yet")
                logger.warning("VadManager or stream state not initialized")
                return
            }

            print("🔍 VADDetector: Processing \(floatArray.count) samples with FluidAudio VAD")

            do {
                // Process the audio chunk with VAD config (already set during initialization)
                let result = try await manager.processStreamingChunk(
                    floatArray,
                    state: state
                )

                print("🔍 VADDetector: VAD probability: \(result.probability)")

                // Update our state reference
                self.streamState = result.state

                // Handle speech events
                if let event = result.event {
                    print("🔍 VADDetector: Got event: \(event.kind)")
                    switch event.kind {
                    case .speechStart:
                        self.handleVoiceStarted()
                    case .speechEnd:
                        self.handleVoiceEnded()
                    }
                } else {
                    print("🔍 VADDetector: No event")
                }

                logger.debug("VAD probability: \(result.probability)")

            } catch {
                print("❌ VADDetector: Error processing audio: \(error.localizedDescription)")
                logger.error("Error processing audio with VAD: \(error.localizedDescription)")
            }
        }

        return .continue
    }

    func processFrame(_ frame: [Int16]) -> Bool {
        // This method is no longer used directly since VadManager handles detection
        // Keep for compatibility
        return isProcessingVoice
    }

    // MARK: - Internal handlers (replaces VADDelegate)

    private func handleVoiceStarted() {
        print("🗣️ VADDetector: SPEECH START event")
        logger.info("Voice started detected by FluidAudio VAD")

        if state == .idle {
            state = .speechDetected
            speechStartTime = Date()
            // Don't clear currentAudioChunk - it already contains pre-speech audio
            isProcessingVoice = true

            let chunkSize = Float(currentAudioChunk.count) / (16000.0 * 4.0)
            print("🗣️ VADDetector: Speech detected with \(String(format: "%.2f", chunkSize))s of pre-speech audio")
            logger.info("Speech detected with \(chunkSize, format: .fixed(precision: 2))s of pre-speech audio")
        } else {
            print("🗣️ VADDetector: Speech start ignored, already in state: \(state)")
        }
    }

    private func handleVoiceEnded() {
        print("🔇 VADDetector: SPEECH END event")
        logger.info("Voice ended detected by FluidAudio VAD")

        isProcessingVoice = false

        // Check if we have valid speech duration
        if let speechStart = speechStartTime {
            let speechDuration = Date().timeIntervalSince(speechStart)
            print("🔇 VADDetector: Speech duration: \(String(format: "%.2f", speechDuration))s, min required: \(Config.vadMinSpeechDuration)s")

            if speechDuration >= Config.vadMinSpeechDuration {
                let totalChunkSize = Float(currentAudioChunk.count) / (16000.0 * 4.0)
                print("✅ VADDetector: Speech segment valid! Duration=\(String(format: "%.2f", speechDuration))s, chunk=\(String(format: "%.2f", totalChunkSize))s")
                logger.info("Speech segment complete: duration=\(speechDuration)s, total chunk=\(totalChunkSize, format: .fixed(precision: 2))s")

                // Use our accumulated chunk which includes pre-speech audio
                if !self.currentAudioChunk.isEmpty {
                    print("📤 VADDetector: Emitting chunk with \(self.currentAudioChunk.count) bytes")
                    logger.info("Emitting chunk with \(self.currentAudioChunk.count) bytes")
                    onChunkReady?(self.currentAudioChunk)
                } else {
                    print("⚠️ VADDetector: Chunk is empty, not emitting")
                }

                // Reset state
                reset()
            } else {
                print("❌ VADDetector: Speech segment too short: \(String(format: "%.2f", speechDuration))s, discarding")
                logger.debug("Speech segment too short: \(speechDuration)s, discarding")
                reset()
            }
        } else {
            print("⚠️ VADDetector: Speech end but no start time recorded")
        }
    }
}
