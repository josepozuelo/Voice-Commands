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
    
    // Remove pre-trigger buffer - we'll continuously record everything
    
    // For debugging
    private var lastThresholdLogTime = Date()
    private let thresholdLogInterval: TimeInterval = 2.0
    
    // Track if we have any audio accumulated
    private var hasAccumulatedAudio = false
    
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
        isContinuousMode = true
        hasAccumulatedAudio = false
        
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
            // Always accumulate audio while in continuous mode
            currentChunkBuffer.append(convertedData)
            
            // Process with VAD detector
            let result = vadDetector.processAudioData(convertedData)
            
            // Track if we're accumulating speech
            if vadDetector.state == .speechDetected || vadDetector.state == .trailingSilence {
                hasAccumulatedAudio = true
            }
            
            // Log VAD state periodically for debugging
            if Date().timeIntervalSince(lastThresholdLogTime) >= thresholdLogInterval {
                print("VAD state: \(vadDetector.state), RMS: \(rms), Buffer size: \(currentChunkBuffer.count)")
                lastThresholdLogTime = Date()
            }
            
            // Only send chunk when VAD indicates complete speech segment
            if result == .chunkReady && hasAccumulatedAudio && !currentChunkBuffer.isEmpty {
                print("DEBUG: Sending complete audio chunk of size: \(currentChunkBuffer.count) bytes")
                audioChunkPublisher.send(currentChunkBuffer)
                currentChunkBuffer.removeAll()
                hasAccumulatedAudio = false
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