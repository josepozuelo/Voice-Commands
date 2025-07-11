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
    private var hasDetectedSpeech = false
    private var silenceStartTime: Date?
    private var chunkStartTime: Date?
    private var currentChunkBuffer = Data()
    private var silenceTimer: Timer?
    
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
        hasDetectedSpeech = false
        chunkStartTime = Date()
        silenceStartTime = nil
        
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
            
            // Check if this is speech
            if rms >= Config.speechDetectionThreshold {
                hasDetectedSpeech = true
                silenceStartTime = nil  // Reset silence timer when speech detected
            }
            
            // Only process silence if we've detected speech first
            if hasDetectedSpeech {
                // Check if we're in silence
                if rms < Config.silenceRMSThreshold {
                    // We're in silence
                    if silenceStartTime == nil {
                        silenceStartTime = Date()
                    }
                    
                    // Check if silence duration has been met
                    if let silenceStart = silenceStartTime,
                       Date().timeIntervalSince(silenceStart) >= Config.silenceDuration {
                        processSilenceDetected()
                    }
                } else {
                    // Not in silence, reset silence timer
                    silenceStartTime = nil
                }
            }
            
            // Check for maximum chunk duration (only if speech detected)
            if hasDetectedSpeech,
               let chunkStart = chunkStartTime,
               Date().timeIntervalSince(chunkStart) >= Config.maxAudioChunkDuration {
                processChunkTimeout()
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
    
    private func processSilenceDetected() {
        // Check if we have enough audio for a valid chunk
        guard currentChunkBuffer.count > 0,
              let chunkStart = chunkStartTime,
              Date().timeIntervalSince(chunkStart) >= Config.minAudioChunkDuration else {
            return
        }
        
        // Send the chunk
        audioChunkPublisher.send(currentChunkBuffer)
        
        // Reset for next chunk
        currentChunkBuffer.removeAll()
        hasDetectedSpeech = false  // Reset speech detection for next chunk
        chunkStartTime = Date()
        silenceStartTime = nil
    }
    
    private func processChunkTimeout() {
        // Force send chunk when max duration reached
        if !currentChunkBuffer.isEmpty {
            audioChunkPublisher.send(currentChunkBuffer)
            currentChunkBuffer.removeAll()
            hasDetectedSpeech = false  // Reset speech detection for next chunk
            chunkStartTime = Date()
            silenceStartTime = nil
        }
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