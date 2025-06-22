import Foundation
import OSLog

private let logger = Logger(subsystem: "com.yourteam.VoiceControl", category: "VADChunker")

class VADChunker {
    // Level 2: Counter-Based Tracking
    private var voiceFrameCount = 0      // consecutive voiced frames (resets on silence)
    private var silenceFrameCount = 0    // consecutive unvoiced frames (resets on voice)
    private var totalSpeechFrames = 0    // cumulative voiced frames in chunk (for validation)
    
    // Level 3: Chunk-Level State
    private var inSpeech = false         // boolean gate: are we currently recording speech?
    private var currentChunk: [Float] = []  // audio buffer accumulating all frames
    
    // Timing
    private var chunkStartTime: Date?
    private var lastDebugLogTime = Date()
    
    // Dependencies
    private let vadDetector = VADSilenceDetector()
    private let audioPreprocessor = AudioPreprocessor()
    
    // Parameters (from spec)
    private let minSpeechFrames = 5       // 100ms: ignores coughs/clicks
    private let trailingSilenceFrames = 25  // 500ms: utterance-end threshold
    private let maxChunkLength: TimeInterval = 10.0  // Safety cutoff
    
    // Chunk emission callback
    var onChunkReady: ((Data) -> Void)?
    
    init() {
        logger.info("VADChunker initialized with minSpeechFrames=\(self.minSpeechFrames), trailingSilenceFrames=\(self.trailingSilenceFrames)")
    }
    
    func processAudioBuffer(_ buffer: [Float]) {
        // Always append to current chunk (continuous recording)
        currentChunk.append(contentsOf: buffer)
        
        // Level 1: Frame-Level Detection
        let (frames, _) = audioPreprocessor.processAudioBuffer(buffer)
        
        for frame in frames {
            let isVoiced = processFrame(frame)
            
            // Level 2: Counter tracking
            if isVoiced {
                voiceFrameCount += 1
                silenceFrameCount = 0
                totalSpeechFrames += 1
                
                // Transition check: Not Speaking → Speaking
                if voiceFrameCount == minSpeechFrames {
                    inSpeech = true
                    if chunkStartTime == nil {
                        chunkStartTime = Date()
                    }
                    logger.info("Speech started: transitioning to inSpeech state")
                }
            } else {
                silenceFrameCount += 1
                voiceFrameCount = 0
            }
            
            // Level 3: Chunk emission logic
            if inSpeech && silenceFrameCount >= trailingSilenceFrames {
                emitChunkIfSpeech()
                resetState()
            }
            
            // Safety cutoff
            if let startTime = chunkStartTime, 
               Date().timeIntervalSince(startTime) >= maxChunkLength {
                logger.warning("Chunk reached max length (\(self.maxChunkLength)s), forcing emission")
                emitChunkIfSpeech()
                resetState()
            }
        }
        
        // Debug logging every 2 seconds
        if Date().timeIntervalSince(lastDebugLogTime) >= 2.0 {
            logger.debug("VAD — voiced:\(self.voiceFrameCount)  silence:\(self.silenceFrameCount)  inSpeech:\(self.inSpeech)  totalSpeech:\(self.totalSpeechFrames)")
            lastDebugLogTime = Date()
        }
    }
    
    private func processFrame(_ frame: [Int16]) -> Bool {
        // Use existing VAD detector's frame processing
        return vadDetector.processFrame(frame)
    }
    
    private func emitChunkIfSpeech() {
        // Chunk validation: only emit if totalSpeechFrames >= minSpeechFrames
        guard totalSpeechFrames >= minSpeechFrames else {
            logger.debug("Chunk discarded: insufficient speech frames (\(self.totalSpeechFrames) < \(self.minSpeechFrames))")
            return
        }
        
        guard !currentChunk.isEmpty else {
            logger.debug("Chunk discarded: empty audio buffer")
            return
        }
        
        // Trim leading and trailing silence
        let trimmedChunk = trimSilence(from: currentChunk)
        
        // Convert to Data for emission
        let chunkData = trimmedChunk.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        logger.info("Emitting chunk: duration=\(Double(trimmedChunk.count) / Config.audioSampleRate)s, speechFrames=\(self.totalSpeechFrames)")
        
        // Emit the chunk
        onChunkReady?(chunkData)
    }
    
    private func trimSilence(from audio: [Float]) -> [Float] {
        // Simple energy-based silence trimming
        let energyThreshold: Float = 0.01
        
        // Find first non-silent sample
        var startIndex = 0
        for i in 0..<audio.count {
            if abs(audio[i]) > energyThreshold {
                startIndex = max(0, i - Int(Config.audioSampleRate * 0.1)) // Keep 100ms before speech
                break
            }
        }
        
        // Find last non-silent sample
        var endIndex = audio.count - 1
        for i in stride(from: audio.count - 1, through: 0, by: -1) {
            if abs(audio[i]) > energyThreshold {
                endIndex = min(audio.count - 1, i + Int(Config.audioSampleRate * 0.1)) // Keep 100ms after speech
                break
            }
        }
        
        guard startIndex < endIndex else {
            return audio
        }
        
        return Array(audio[startIndex...endIndex])
    }
    
    private func resetState() {
        // Reset all state variables
        voiceFrameCount = 0
        silenceFrameCount = 0
        totalSpeechFrames = 0
        inSpeech = false
        currentChunk.removeAll()
        chunkStartTime = nil
        
        logger.debug("VADChunker state reset")
    }
    
    func reset() {
        resetState()
        vadDetector.reset()
        logger.info("VADChunker fully reset")
    }
}