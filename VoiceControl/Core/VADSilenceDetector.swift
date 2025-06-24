import Foundation
import os.log
import RealTimeCutVADLibrary

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
    private let audioPreprocessor: AudioPreprocessor
    
    private var vadManager: VADWrapper?
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
        self.audioPreprocessor = AudioPreprocessor()
        super.init()
        
        // Initialize VAD Manager
        self.vadManager = VADWrapper()
        self.vadManager?.delegate = self
        
        // Use Silero v5 (more permissive than v4)
        self.vadManager?.setSileroModel(.v5)
        
        // Set sample rate to 16kHz (required by our audio pipeline)
        self.vadManager?.setSamplerate(.SAMPLERATE_16)
        
        // Optional: Configure detection thresholds for slightly aggressive mode
        // These values provide a balance between sensitivity and false positives
        self.vadManager?.setThresholdWithVadStartDetectionProbability(
            0.7,   // Start detection probability threshold
            vadEndDetectionProbability: 0.7,   // End detection probability threshold
            voiceStartVadTrueRatio: 0.5,   // 50% of frames must exceed threshold to start (v5 default)
            voiceEndVadFalseRatio: 0.95,  // 95% of frames must be below threshold to end
            voiceStartFrameCount: 10,    // 10 frames (0.32s) to confirm speech start
            voiceEndFrameCount: 57     // 57 frames (1.8s) to confirm speech end
        )
        
        logger.info("VADSilenceDetector initialized with Silero v5")
    }
    
    func reset() {
        state = .idle
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        silenceStartTime = nil
        speechStartTime = nil
        currentAudioChunk = Data()
        isProcessingVoice = false
        logger.info("VADSilenceDetector reset")
    }
    
    func process(rms: Float, timestamp: Date) -> DetectionResult {
        // This method is for compatibility with DynamicSilenceDetector interface
        // VAD doesn't use RMS, so we just return continue
        return .continue
    }
    
    func processAudioData(_ audioData: Data) -> DetectionResult {
        // Convert Data to Float array
        let floatArray = audioData.withUnsafeBytes { bytes in
            Array(bytes.bindMemory(to: Float.self))
        }
        
        // Process with VAD - it expects a pointer to Float array and count
        floatArray.withUnsafeBufferPointer { buffer in
            if let baseAddress = buffer.baseAddress {
                vadManager?.processAudioData(withBuffer: baseAddress, count: UInt(buffer.count))
            }
        }
        
        // ALWAYS accumulate audio regardless of state to ensure no audio is lost
        currentAudioChunk.append(audioData)
        
        
        return .continue
    }
    
    func processFrame(_ frame: [Int16]) -> Bool {
        // This method is no longer used directly since VADWrapper handles detection
        // Keep for compatibility
        return isProcessingVoice
    }
}

// MARK: - VADDelegate
extension VADSilenceDetector: VADDelegate {
    func voiceStarted() {
        logger.info("Voice started detected by Silero VAD")
        
        if state == .idle {
            state = .speechDetected
            speechStartTime = Date()
            // Don't clear currentAudioChunk - it already contains pre-speech audio
            isProcessingVoice = true
            
            let chunkSize = Float(currentAudioChunk.count) / (16000.0 * 4.0)
            logger.info("Speech detected with \(chunkSize, format: .fixed(precision: 2))s of pre-speech audio")
        }
    }
    
    func voiceEnded(withWavData wavData: Data!) {
        logger.info("Voice ended detected by Silero VAD")
        
        isProcessingVoice = false
        
        // Check if we have valid speech duration
        if let speechStart = speechStartTime {
            let speechDuration = Date().timeIntervalSince(speechStart)
            
            if speechDuration >= Config.vadMinSpeechDuration {
                let totalChunkSize = Float(currentAudioChunk.count) / (16000.0 * 4.0)
                logger.info("Speech segment complete: duration=\(speechDuration)s, total chunk=\(totalChunkSize, format: .fixed(precision: 2))s")
                
                // Use our accumulated chunk which includes pre-speech audio
                if !self.currentAudioChunk.isEmpty {
                    logger.info("Emitting chunk with \(self.currentAudioChunk.count) bytes")
                    onChunkReady?(self.currentAudioChunk)
                }
                
                // Reset state
                reset()
            } else {
                logger.debug("Speech segment too short: \(speechDuration)s, discarding")
                reset()
            }
        }
    }
    
    func voiceDidContinue(withPCMFloat pcmFloatData: Data!) {
        // This provides real-time PCM data during voice activity
        // We can use this for live processing if needed
    }
}