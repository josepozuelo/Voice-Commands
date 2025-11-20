import Foundation
import AVFoundation
import Combine

enum AudioEngineError: LocalizedError {
    case failedToInitialize
    case failedToStart(Error)
    case noRecordedAudio
    
    var errorDescription: String? {
        switch self {
        case .failedToInitialize:
            return "Failed to initialize audio engine"
        case .failedToStart(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noRecordedAudio:
            return "No audio was recorded"
        }
    }
}

class AudioEngine: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0
    
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer = Data()
    
    var audioChunkPublisher = PassthroughSubject<Data, Never>()  // For continuous mode chunks
    
    private let bufferSize = AVAudioFrameCount(Config.audioBufferSize)
    private let sampleRate = Config.audioSampleRate
    
    // Continuous mode properties
    private var isContinuousMode = false
    
    // VAD-based chunking
    private var vadChunker = VADChunker()
    
    // Debug counters
    private var processedBufferCount = 0
    private var totalProcessedSamples = 0
    
    override init() {
        super.init()
        setupAudioSession()
        
        // Setup VAD chunker callback
        vadChunker.onChunkReady = { [weak self] chunkData in
            guard let self = self else { return }
            let seconds = Float(chunkData.count) / (16000.0 * 4.0)
            print("🎤 VOICE DETECTED: Sending \(String(format: "%.1f", seconds))s chunk to Whisper")
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
    
    func startRecording(enableSilenceDetection: Bool, maxDuration: TimeInterval? = nil) async throws {
        guard !isRecording else {
            print("🎤 AUDIO ENGINE: Already recording, skipping start")
            return
        }

        print("🎙️ AUDIO ENGINE: Starting recording (silence detection: \(enableSilenceDetection))")

        audioBuffer.removeAll()
        isContinuousMode = enableSilenceDetection

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioEngineError.failedToInitialize
        }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            throw AudioEngineError.failedToInitialize
        }

        // Use the input node's native format to avoid format mismatch
        let inputFormat = inputNode.outputFormat(forBus: 0)

        print("🎤 AUDIO ENGINE: Input format - sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")

        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        // Prepare the engine before starting
        audioEngine.prepare()

        do {
            try audioEngine.start()
            print("🎤 AUDIO ENGINE: Engine started successfully")
            await MainActor.run {
                self.isRecording = true
            }

            // Handle max duration if specified
            if let maxDuration = maxDuration {
                Task {
                    try await Task.sleep(nanoseconds: UInt64(maxDuration * 1_000_000_000))
                    await self.stopRecording()
                }
            }
        } catch {
            print("❌ AUDIO ENGINE: Failed to start: \(error)")
            throw AudioEngineError.failedToStart(error)
        }
    }
    
    func startContinuousRecording() {
        guard !isRecording else {
            print("🎤 AUDIO ENGINE: Already recording, skipping start")
            return
        }

        print("🎤 AUDIO ENGINE: Starting continuous recording")

        // Clear all buffers before starting
        audioBuffer.removeAll()
        isContinuousMode = true

        // Reset debug counters
        processedBufferCount = 0
        totalProcessedSamples = 0

        // Reset VAD chunker to ensure clean state
        vadChunker.reset()

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ AUDIO ENGINE: Failed to create audio engine")
            return
        }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else {
            print("❌ AUDIO ENGINE: Failed to get input node")
            return
        }

        // Use the input node's native format to avoid format mismatch
        let inputFormat = inputNode.outputFormat(forBus: 0)

        print("🎤 AUDIO ENGINE: Input format - sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")
        print("🎤 AUDIO ENGINE: Installing tap with buffer size: \(bufferSize)")

        // IMPORTANT: Install tap BEFORE starting the engine
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        // Prepare the engine before starting
        audioEngine.prepare()
        print("🎤 AUDIO ENGINE: Engine prepared")

        do {
            try audioEngine.start()
            print("🎤 AUDIO ENGINE: Engine started successfully")
            DispatchQueue.main.async {
                self.isRecording = true
                print("🎤 AUDIO ENGINE: isRecording set to true")
            }
        } catch {
            print("❌ AUDIO ENGINE: Failed to start audio engine: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        
        
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
        }

        // Don't clear the buffer immediately - let getRecordedAudio() retrieve it first
        // The buffer will be cleared when starting a new recording

        // Reset continuous mode flag after processing
        isContinuousMode = false

        // Reset VAD chunker
        vadChunker.reset()
    }
    
    func stopRecording() async {
        await MainActor.run {
            self.stopRecording()
        }
    }
    
    func getRecordedAudio() async -> Data? {
        guard !audioBuffer.isEmpty else { return nil }
        let recordedData = audioBuffer
        audioBuffer.removeAll()  // Clear buffer after retrieving
        return recordedData
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            print("⚠️ AUDIO ENGINE: No channel data in buffer")
            return
        }

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

            // Update debug counters
            processedBufferCount += 1
            totalProcessedSamples += floatArray.count

            // Log every ~1 second of audio
            if processedBufferCount % 50 == 0 { // ~50 buffers = ~1 second at typical buffer sizes
                let totalSeconds = Float(totalProcessedSamples) / 16000.0
                print("🎤 AUDIO ENGINE: Processed \(processedBufferCount) buffers, \(String(format: "%.1f", totalSeconds))s total audio")
            }

            print("🎤 AUDIO ENGINE: Sending \(floatArray.count) samples to VAD chunker (continuous mode)")
            // Process with VAD chunker
            vadChunker.processAudioBuffer(floatArray)
        } else {
            // For non-continuous mode (Edit/Dictation), just buffer the audio
            audioBuffer.append(convertedData)
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