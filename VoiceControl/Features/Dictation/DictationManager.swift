import Foundation
import Combine
import SwiftUI

enum DictationState: Equatable {
    case idle
    case recording(startTime: Date)
    case processing
    case error(String)
    
    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }
}

@MainActor
class DictationManager: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published var showHUD = false
    @Published var amplitudeSamples: [Float] = []

    private let audioEngine: AudioEngine
    private let whisperService: WhisperService
    private let accessibilityBridge: AccessibilityBridge
    private let gptService: GPTService
    var cancellables = Set<AnyCancellable>()

    // Track if continuous mode should be resumed after dictation
    private var shouldResumeContinuousMode = false

    // Track recording start time for duration calculation
    private var recordingStartTime: Date?

    // Prevent re-entrant cancel calls
    private var isCancelling = false

    // Waveform configuration
    private let maxAmplitudeSamples = 30

    weak var commandManager: CommandManager?
    weak var historyManager: DictationHistoryManager?

    init(audioEngine: AudioEngine, whisperService: WhisperService, accessibilityBridge: AccessibilityBridge, gptService: GPTService) {
        self.audioEngine = audioEngine
        self.whisperService = whisperService
        self.accessibilityBridge = accessibilityBridge
        self.gptService = gptService

        setupBindings()
    }
    
    private func setupBindings() {
        // Subscribe to audio level changes for waveform visualization
        audioEngine.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                // Only track amplitude when recording
                if case .recording = self.state {
                    self.amplitudeSamples.append(level)
                    // Keep only the most recent samples
                    if self.amplitudeSamples.count > self.maxAmplitudeSamples {
                        self.amplitudeSamples.removeFirst()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func startDictation() async {
        do {
            // If already recording, toggle it off (submit the dictation)
            if case .recording = state {
                await stopDictation()
                return
            }
            
            // Check if continuous mode is currently active
            shouldResumeContinuousMode = commandManager?.isContinuousMode ?? false
            print("🎤 DictationManager: Starting dictation")
            print("   CommandManager continuous mode: \(commandManager?.isContinuousMode ?? false)")
            print("   Should resume continuous mode: \(shouldResumeContinuousMode)")

            // Clear previous amplitude samples
            amplitudeSamples.removeAll()

            recordingStartTime = Date()
            state = .recording(startTime: recordingStartTime!)
            showHUD = true

            try await audioEngine.startRecording(
                enableSilenceDetection: false,
                maxDuration: Config.DictationMode.maxRecordingDuration
            )
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
            showHUD = true
        }
    }
    
    
    func toggleDictation() async {
        // This method is specifically for handling Control+K during dictation
        if case .recording = state {
            // If recording, stop and process the dictation
            await stopDictation()
        } else {
            // If not recording, start dictation
            await startDictation()
        }
    }
    
    func stopDictation() async {
        await audioEngine.stopRecording()
        if case .recording = state {
            await processDictation()
        }
    }
    
    func cancelDictation() async {
        // Prevent re-entrant calls
        guard !isCancelling else { return }
        isCancelling = true

        await audioEngine.stopRecording()

        // Add a small delay to ensure audio engine has fully stopped
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Batch all state updates in a single animation transaction
        // This prevents multiple constraint update passes in the NSPanel
        await withAnimation {
            self.recordingStartTime = nil
            self.amplitudeSamples.removeAll()
            self.state = .idle
            self.showHUD = false
        }

        self.isCancelling = false

        // Return to continuous mode if it was active before
        if self.shouldResumeContinuousMode {
            NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
            self.shouldResumeContinuousMode = false
        }
    }
    
    private func processDictation() async {
        let pipelineStartTime = Date()
        print("⏱️ [DICTATION PIPELINE] Starting at \(pipelineStartTime)")

        state = .processing

        do {
            // Stage 1: Get audio data
            let stage1Start = Date()
            guard let audioData = await audioEngine.getRecordedAudio() else {
                throw NSError(domain: "DictationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio recorded"])
            }
            let stage1Duration = Date().timeIntervalSince(stage1Start)
            print("⏱️ [STAGE 1] Audio retrieval: \(String(format: "%.3f", stage1Duration))s")

            // Calculate duration
            let duration: TimeInterval
            if let startTime = recordingStartTime {
                duration = Date().timeIntervalSince(startTime)
            } else {
                duration = 0
            }

            // Stage 2: Whisper transcription
            let stage2Start = Date()
            var transcribedText = try await whisperService.transcribe(audioData: audioData)
            let stage2Duration = Date().timeIntervalSince(stage2Start)
            print("⏱️ [STAGE 2] Whisper transcription: \(String(format: "%.3f", stage2Duration))s - Result: '\(transcribedText.prefix(50))'")

            // Stage 3: GPT formatting
            var formattedText: String? = nil
            var stage3Duration: TimeInterval = 0
            if Config.DictationMode.formatWithGPT {
                let stage3Start = Date()
                formattedText = try await gptService.formatDictation(transcribedText)
                stage3Duration = Date().timeIntervalSince(stage3Start)
                print("⏱️ [STAGE 3] GPT formatting: \(String(format: "%.3f", stage3Duration))s - Result: '\(formattedText?.prefix(50) ?? "nil")'")
            } else {
                print("⏱️ [STAGE 3] GPT formatting: SKIPPED (disabled in config)")
            }

            let textToInsert = formattedText ?? transcribedText

            // Stage 4: Text insertion
            let stage4Start = Date()
            try accessibilityBridge.insertTextAtCursor(textToInsert)
            let stage4Duration = Date().timeIntervalSince(stage4Start)
            print("⏱️ [STAGE 4] Text insertion: \(String(format: "%.3f", stage4Duration))s")

            // Stage 5: History storage
            let stage5Start = Date()
            if Config.History.enableHistory, let historyManager = historyManager {
                historyManager.saveEntry(
                    transcribedText: transcribedText,
                    audioData: audioData,
                    duration: duration,
                    formattedText: formattedText
                )
            }
            let stage5Duration = Date().timeIntervalSince(stage5Start)
            print("⏱️ [STAGE 5] History storage: \(String(format: "%.3f", stage5Duration))s")

            // Total pipeline duration
            let totalDuration = Date().timeIntervalSince(pipelineStartTime)
            print("⏱️ [PIPELINE COMPLETE] Total: \(String(format: "%.3f", totalDuration))s | Breakdown: Audio=\(String(format: "%.3f", stage1Duration))s, Whisper=\(String(format: "%.3f", stage2Duration))s, GPT=\(String(format: "%.3f", stage3Duration))s, Insert=\(String(format: "%.3f", stage4Duration))s, History=\(String(format: "%.3f", stage5Duration))s")

            // Reset recording start time
            recordingStartTime = nil

            state = .idle
            showHUD = false

            // Return to continuous mode if it was active before
            if shouldResumeContinuousMode {
                print("🎤 DictationManager: Posting resumeContinuousMode notification")
                NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
                shouldResumeContinuousMode = false
            } else {
                print("🎤 DictationManager: Not resuming continuous mode (was not active before)")
            }
        } catch {
            let totalDuration = Date().timeIntervalSince(pipelineStartTime)
            print("⏱️ [PIPELINE ERROR] Failed after \(String(format: "%.3f", totalDuration))s: \(error.localizedDescription)")
            recordingStartTime = nil
            state = .error("Transcription failed: \(error.localizedDescription)")
        }
    }
    
    func resetState() {
        state = .idle
        showHUD = false
    }
}

