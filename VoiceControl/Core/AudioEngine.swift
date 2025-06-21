import Foundation
import AVFoundation
import Combine

// MARK: - Adaptive Noise Tracking

struct AdaptiveNoiseTracker {
    private var rmsHistory: CircularBuffer<Float>
    private let historyCapacity = 160 // 10 seconds at 16Hz
    private let shortTermSamples = 16 // ~1 second
    
    private(set) var longTermAverage: Float = 0
    private(set) var shortTermAverage: Float = 0
    private(set) var standardDeviation: Float = 0
    private(set) var noiseFloor: Float = 0
    
    init() {
        self.rmsHistory = CircularBuffer<Float>(capacity: historyCapacity)
    }
    
    mutating func update(rms: Float) {
        rmsHistory.append(rms)
        
        let allSamples = rmsHistory.allElements()
        guard !allSamples.isEmpty else { return }
        
        // Calculate long-term average
        longTermAverage = allSamples.reduce(0, +) / Float(allSamples.count)
        
        // Calculate short-term average
        let recentSamples = rmsHistory.suffix(shortTermSamples)
        if !recentSamples.isEmpty {
            shortTermAverage = recentSamples.reduce(0, +) / Float(recentSamples.count)
        }
        
        // Calculate standard deviation
        let squaredDiffs = allSamples.map { pow($0 - longTermAverage, 2) }
        let variance = squaredDiffs.reduce(0, +) / Float(allSamples.count)
        standardDeviation = sqrt(variance)
        
        // Calculate noise floor (5th percentile)
        let sortedSamples = allSamples.sorted()
        let percentileIndex = max(0, Int(Float(sortedSamples.count) * 0.05) - 1)
        noiseFloor = sortedSamples[percentileIndex]
    }
}

// MARK: - Dynamic Silence Detection

class DynamicSilenceDetector {
    enum DetectionState {
        case calibrating
        case waitingForSpeech
        case detectingSpeech
        case trailingSilence
    }
    
    enum DetectionResult {
        case `continue`
        case chunkReady
    }
    
    private var state: DetectionState = .calibrating
    private var noiseTracker = AdaptiveNoiseTracker()
    private var calibrationStartTime: Date?
    private var speechStartTime: Date?
    private var silenceStartTime: Date?
    private var confirmationCount = 0
    
    // Configuration
    private let calibrationDuration: TimeInterval = Config.calibrationDuration
    private let minSpeechDuration: TimeInterval = Config.minSpeechDuration
    private let silenceDuration: TimeInterval = Config.adaptiveSilenceDuration
    private let confirmationSamples = Config.confirmationSamples
    private let speechMultiplier: Float = Config.speechMultiplier
    private let silenceMultiplier: Float = Config.silenceMultiplier
    private let minThreshold: Float = 0.01
    private let maxThreshold: Float = 0.5
    
    private(set) var currentSpeechThreshold: Float = 0.1
    private(set) var currentSilenceThreshold: Float = 0.05
    
    func reset() {
        state = .calibrating
        calibrationStartTime = Date()
        speechStartTime = nil
        silenceStartTime = nil
        confirmationCount = 0
    }
    
    func process(rms: Float, timestamp: Date) -> DetectionResult {
        // Update noise statistics
        noiseTracker.update(rms: rms)
        
        // Update dynamic thresholds
        updateThresholds()
        
        switch state {
        case .calibrating:
            if calibrationStartTime == nil {
                calibrationStartTime = timestamp
            }
            
            if let startTime = calibrationStartTime,
               timestamp.timeIntervalSince(startTime) >= calibrationDuration {
                state = .waitingForSpeech
            }
            return .continue
            
        case .waitingForSpeech:
            if rms >= currentSpeechThreshold {
                confirmationCount += 1
                if confirmationCount >= confirmationSamples {
                    state = .detectingSpeech
                    speechStartTime = timestamp
                    confirmationCount = 0
                }
            } else {
                confirmationCount = 0
            }
            return .continue
            
        case .detectingSpeech:
            if rms < currentSilenceThreshold {
                if silenceStartTime == nil {
                    silenceStartTime = timestamp
                }
                state = .trailingSilence
            }
            return .continue
            
        case .trailingSilence:
            if rms >= currentSpeechThreshold {
                // Speech resumed
                state = .detectingSpeech
                silenceStartTime = nil
            } else if let silenceStart = silenceStartTime,
                      timestamp.timeIntervalSince(silenceStart) >= silenceDuration {
                // Check minimum speech duration
                if let speechStart = speechStartTime,
                   timestamp.timeIntervalSince(speechStart) >= minSpeechDuration {
                    // Valid chunk detected
                    state = .waitingForSpeech
                    speechStartTime = nil
                    silenceStartTime = nil
                    return .chunkReady
                } else {
                    // Too short, reset
                    state = .waitingForSpeech
                    speechStartTime = nil
                    silenceStartTime = nil
                }
            }
            return .continue
        }
    }
    
    private func updateThresholds() {
        let baseline = noiseTracker.longTermAverage
        let stdDev = noiseTracker.standardDeviation
        
        // Calculate speech threshold
        let adaptiveSpeechThreshold = max(
            baseline + 2 * stdDev,
            baseline * speechMultiplier
        )
        currentSpeechThreshold = min(max(adaptiveSpeechThreshold, minThreshold), maxThreshold)
        
        // Calculate silence threshold
        let adaptiveSilenceThreshold = baseline + 0.5 * stdDev
        currentSilenceThreshold = min(max(adaptiveSilenceThreshold, minThreshold), maxThreshold)
    }
}

class AudioEngine: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer = Data()
    
    var audioDataPublisher = PassthroughSubject<Data, Never>()
    var recordingCompletePublisher = PassthroughSubject<Data, Never>()
    var audioChunkPublisher = PassthroughSubject<Data, Never>()  // For continuous mode chunks
    
    private let bufferSize = AVAudioFrameCount(Config.audioBufferSize)
    private let sampleRate = Config.audioSampleRate
    
    // Continuous mode properties
    private var isContinuousMode = false
    private var currentChunkBuffer = Data()
    private var silenceTimer: Timer?
    
    // Dynamic silence detection
    private var dynamicDetector = DynamicSilenceDetector()
    
    // For debugging
    private var lastThresholdLogTime = Date()
    private let thresholdLogInterval: TimeInterval = 2.0
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if os(macOS)
        // macOS doesn't use AVAudioSession
        #else
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .spokenAudio, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #endif
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        audioBuffer.removeAll()
        isContinuousMode = false
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }
        
        // Use the input node's native format to avoid format mismatch
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func startContinuousRecording() {
        guard !isRecording else { return }
        
        audioBuffer.removeAll()
        currentChunkBuffer.removeAll()
        isContinuousMode = true
        dynamicDetector.reset()
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }
        
        // Use the input node's native format to avoid format mismatch
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        isRecording = false
        isContinuousMode = false
        
        if isContinuousMode && !currentChunkBuffer.isEmpty {
            // Send any remaining chunk
            audioChunkPublisher.send(currentChunkBuffer)
            currentChunkBuffer.removeAll()
        } else if !audioBuffer.isEmpty {
            recordingCompletePublisher.send(audioBuffer)
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        
        DispatchQueue.main.async {
            self.audioLevel = rms
        }
        
        // Convert to target sample rate if needed
        let convertedData = convertToTargetSampleRate(buffer)
        
        if isContinuousMode {
            // Add to current chunk buffer
            currentChunkBuffer.append(convertedData)
            
            // Process with dynamic detector
            let result = dynamicDetector.process(rms: rms, timestamp: Date())
            
            // Log thresholds periodically for debugging
            if Date().timeIntervalSince(lastThresholdLogTime) >= thresholdLogInterval {
                print("Dynamic thresholds - Speech: \(dynamicDetector.currentSpeechThreshold), Silence: \(dynamicDetector.currentSilenceThreshold), Current RMS: \(rms)")
                lastThresholdLogTime = Date()
            }
            
            if result == .chunkReady {
                // Send the chunk
                if !currentChunkBuffer.isEmpty {
                    audioChunkPublisher.send(currentChunkBuffer)
                    currentChunkBuffer.removeAll()
                }
            }
        } else {
            // Normal recording mode
            audioBuffer.append(convertedData)
            audioDataPublisher.send(convertedData)
        }
    }
    
    private func convertToTargetSampleRate(_ buffer: AVAudioPCMBuffer) -> Data {
        let inputFormat = buffer.format
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        // If formats match, no conversion needed
        if inputFormat.sampleRate == targetFormat.sampleRate {
            guard let channelData = buffer.floatChannelData else { return Data() }
            let channelDataValue = channelData.pointee
            return Data(bytes: channelDataValue, count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
        
        // Simple downsampling for now (could be improved with proper filtering)
        guard let channelData = buffer.floatChannelData else { return Data() }
        let channelDataValue = channelData.pointee
        
        let inputSampleRate = inputFormat.sampleRate
        let outputSampleRate = targetFormat.sampleRate
        let ratio = inputSampleRate / outputSampleRate
        
        let outputFrameCount = Int(Double(buffer.frameLength) / ratio)
        var outputSamples = [Float](repeating: 0, count: outputFrameCount)
        
        for i in 0..<outputFrameCount {
            let inputIndex = Int(Double(i) * ratio)
            if inputIndex < buffer.frameLength {
                outputSamples[i] = channelDataValue[inputIndex]
            }
        }
        
        return Data(bytes: outputSamples, count: outputSamples.count * MemoryLayout<Float>.size)
    }
    
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
        #else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
        #endif
    }
}