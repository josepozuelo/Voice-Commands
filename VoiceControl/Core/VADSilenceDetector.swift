import Foundation
import OSLog
// Note: WebRTCVAD import will be added after the package is installed
// import WebRTCVAD

private let logger = Logger(subsystem: "com.yourteam.VoiceControl", category: "VADSilenceDetector")

class VADSilenceDetector {
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
    
    // VAD instance will be initialized when WebRTCVAD is available
    // private let vad: WebRTCVAD
    
    private var consecutiveSpeechFrames = 0
    private var consecutiveSilenceFrames = 0
    private var silenceStartTime: Date?
    private var speechStartTime: Date?
    
    // For debugging
    private(set) var currentSpeechThreshold: Float = 0.02  // Not used with VAD, kept for compatibility
    private(set) var currentSilenceThreshold: Float = 0.01  // Not used with VAD, kept for compatibility
    
    init() {
        self.audioPreprocessor = AudioPreprocessor()
        
        // Initialize VAD when package is available
        // self.vad = WebRTCVAD()
        // try? vad.setMode(Config.vadMode)
        
        logger.info("VADSilenceDetector initialized with mode: \(Config.vadMode)")
    }
    
    func reset() {
        state = .idle
        consecutiveSpeechFrames = 0
        consecutiveSilenceFrames = 0
        silenceStartTime = nil
        speechStartTime = nil
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
        
        // Process with VAD
        let (frames, _) = audioPreprocessor.processAudioBuffer(floatArray)
        
        for frame in frames {
            let isSpeech = processFrame(frame)
            
            switch state {
            case .idle:
                if isSpeech {
                    consecutiveSpeechFrames += 1
                    consecutiveSilenceFrames = 0
                    
                    if consecutiveSpeechFrames >= Config.vadSpeechFrameThreshold {
                        // Transition to speech detected
                        state = .speechDetected
                        speechStartTime = Date()
                        logger.info("Speech detected, starting capture")
                    }
                } else {
                    consecutiveSpeechFrames = 0
                }
                
            case .speechDetected:
                if !isSpeech {
                    consecutiveSilenceFrames += 1
                    consecutiveSpeechFrames = 0
                    
                    if consecutiveSilenceFrames == 1 {
                        // Transition to trailing silence
                        state = .trailingSilence
                        silenceStartTime = Date()
                        logger.debug("Transitioning to trailing silence")
                    }
                } else {
                    consecutiveSilenceFrames = 0
                    consecutiveSpeechFrames += 1
                }
                
            case .trailingSilence:
                if isSpeech {
                    // Speech resumed
                    consecutiveSpeechFrames += 1
                    consecutiveSilenceFrames = 0
                    
                    if consecutiveSpeechFrames >= 2 {
                        // Back to speech detected
                        state = .speechDetected
                        silenceStartTime = nil
                        logger.debug("Speech resumed during trailing silence")
                    }
                } else {
                    consecutiveSilenceFrames += 1
                    
                    if let silenceStart = silenceStartTime,
                       Date().timeIntervalSince(silenceStart) >= Config.vadSilenceTimeout {
                        // Check if we have valid speech duration
                        if let speechStart = speechStartTime {
                            let speechDuration = Date().timeIntervalSince(speechStart)
                            
                            if speechDuration >= Config.vadMinSpeechDuration {
                                logger.info("Speech segment complete: duration=\(speechDuration)s")
                                
                                // Reset state
                                state = .idle
                                consecutiveSpeechFrames = 0
                                consecutiveSilenceFrames = 0
                                silenceStartTime = nil
                                speechStartTime = nil
                                
                                return .chunkReady
                            } else {
                                logger.debug("Speech segment too short: \(speechDuration)s, discarding")
                                reset()
                            }
                        }
                    }
                }
            }
            
            logger.debug("Frame: isSpeech=\(isSpeech), state=\(String(describing: self.state)), speechFrames=\(self.consecutiveSpeechFrames), silenceFrames=\(self.consecutiveSilenceFrames)")
        }
        
        return .continue
    }
    
    func processFrame(_ frame: [Int16]) -> Bool {
        // Energy-based VAD implementation
        // Calculate RMS energy
        let sumOfSquares = frame.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = sqrt(sumOfSquares / Double(frame.count))
        
        // Dynamic threshold based on noise floor
        let energyThreshold: Double = 1000.0  // Empirically determined threshold
        
        // Additional zero-crossing rate for better speech detection
        var zeroCrossings = 0
        for i in 1..<frame.count {
            if (frame[i-1] >= 0 && frame[i] < 0) || (frame[i-1] < 0 && frame[i] >= 0) {
                zeroCrossings += 1
            }
        }
        let zeroCrossingRate = Double(zeroCrossings) / Double(frame.count)
        
        // Speech typically has higher energy and moderate zero-crossing rate
        let isVoiced = rms > energyThreshold && zeroCrossingRate < 0.5
        
        return isVoiced
    }
}