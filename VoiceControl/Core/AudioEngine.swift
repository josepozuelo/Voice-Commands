import Foundation
import AVFoundation
import Combine

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
    
    // VAD silence detection
    private var vadDetector = VADSilenceDetector()
    
    // Pre-trigger buffer to capture audio before speech is detected
    private var preTriggerBuffer = CircularBuffer<Data>(capacity: 50)  // ~1 second of audio at 20ms frames
    
    // For debugging
    private var lastThresholdLogTime = Date()
    private let thresholdLogInterval: TimeInterval = 2.0
    
    // Chunk separation timing
    private var lastChunkSentTime: Date?
    private let minimumChunkGap: TimeInterval = 0.5  // 500ms minimum gap between chunks for better separation
    
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
        
        // Clear all buffers before starting
        audioBuffer.removeAll()
        currentChunkBuffer.removeAll()
        preTriggerBuffer.clear()
        isContinuousMode = true
        
        // Reset VAD detector to ensure clean state
        vadDetector.reset()
        
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
            print("DEBUG: Started continuous recording with clean buffers")
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
        
        // Check if we were in continuous mode before clearing the flag
        if isContinuousMode && !currentChunkBuffer.isEmpty {
            // Send any remaining chunk
            print("DEBUG: Sending final chunk on stop: \(currentChunkBuffer.count) bytes")
            audioChunkPublisher.send(currentChunkBuffer)
            currentChunkBuffer.removeAll()
        } else if !audioBuffer.isEmpty {
            recordingCompletePublisher.send(audioBuffer)
        }
        
        // Clear all buffers
        currentChunkBuffer.removeAll()
        audioBuffer.removeAll()
        
        // Reset continuous mode flag after processing
        isContinuousMode = false
        
        // Reset VAD detector
        vadDetector.reset()
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
            let previousState = vadDetector.state
            
            // Process with VAD detector
            let result = vadDetector.processAudioData(convertedData)
            
            // Handle state transitions and audio accumulation
            switch (previousState, vadDetector.state) {
            case (.idle, .speechDetected):
                // Speech just started - add pre-trigger buffer to capture the beginning
                print("DEBUG: Speech started, adding pre-trigger buffer")
                for audioData in preTriggerBuffer.allElements() {
                    currentChunkBuffer.append(audioData)
                }
                currentChunkBuffer.append(convertedData)
                
            case (.speechDetected, _), (.trailingSilence, _):
                // Continue accumulating during speech and trailing silence
                currentChunkBuffer.append(convertedData)
                
            case (.idle, .idle):
                // While idle, keep audio in pre-trigger buffer
                preTriggerBuffer.append(convertedData)
                
            default:
                // Other transitions
                currentChunkBuffer.append(convertedData)
            }
            
            // Log VAD state periodically for debugging
            if Date().timeIntervalSince(lastThresholdLogTime) >= thresholdLogInterval {
                print("VAD state: \(vadDetector.state), RMS: \(rms)")
                lastThresholdLogTime = Date()
            }
            
            if result == .chunkReady {
                // Check if enough time has passed since last chunk
                let now = Date()
                if let lastSent = lastChunkSentTime {
                    let timeSinceLastChunk = now.timeIntervalSince(lastSent)
                    if timeSinceLastChunk < minimumChunkGap {
                        print("DEBUG: Skipping chunk - too soon after last chunk (\(timeSinceLastChunk)s)")
                        return
                    }
                }
                
                // Send the chunk
                if !currentChunkBuffer.isEmpty {
                    print("DEBUG: Sending audio chunk of size: \(currentChunkBuffer.count) bytes")
                    audioChunkPublisher.send(currentChunkBuffer)
                    currentChunkBuffer.removeAll()
                    preTriggerBuffer.clear()  // Clear pre-trigger buffer after sending chunk
                    lastChunkSentTime = now
                    
                    // Add a small delay before processing new audio to ensure clean separation
                    // This helps prevent residual audio from being included in the next chunk
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        // Buffer is already cleared, just a timing guard
                    }
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