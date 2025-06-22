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
    
    // VAD-based chunking
    private var vadChunker = VADChunker()
    
    override init() {
        super.init()
        setupAudioSession()
        
        // Setup VAD chunker callback
        vadChunker.onChunkReady = { [weak self] chunkData in
            guard let self = self else { return }
            print("DEBUG: VADChunker emitted chunk of size: \(chunkData.count) bytes")
            self.audioChunkPublisher.send(chunkData)
        }
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
        isContinuousMode = true
        
        // Reset VAD chunker to ensure clean state
        vadChunker.reset()
        
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
        
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        isRecording = false
        
        // Send any recorded audio if not in continuous mode
        if !isContinuousMode && !audioBuffer.isEmpty {
            recordingCompletePublisher.send(audioBuffer)
        }
        
        // Clear audio buffer
        audioBuffer.removeAll()
        
        // Reset continuous mode flag after processing
        isContinuousMode = false
        
        // Reset VAD chunker
        vadChunker.reset()
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
            // Convert to Float array for VADChunker
            let floatArray = convertedData.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self))
            }
            
            // Process with VAD chunker
            vadChunker.processAudioBuffer(floatArray)
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