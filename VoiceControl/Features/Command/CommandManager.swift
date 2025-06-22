import Foundation
import Combine
import SwiftUI

enum HUDState: Equatable {
    case idle
    case listening
    case continuousListening  // New state for continuous mode
    case processing
    case classifying  // Replaced disambiguating with classifying
    case error(Error)
    
    static func == (lhs: HUDState, rhs: HUDState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.processing, .processing), (.classifying, .classifying), (.continuousListening, .continuousListening):
            return true
        case (.error(_), .error(_)):
            return true
        default:
            return false
        }
    }
}

class CommandManager: ObservableObject {
    @Published var hudState: HUDState = .idle
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var currentCommand: CommandJSON?
    @Published var error: Error?
    @Published var lastTranscription = ""
    @Published var isContinuousMode = false
    
    private let audioEngine = AudioEngine()
    private let whisperService = WhisperService()
    private let commandClassifier = CommandClassifier()
    private let accessibilityBridge = AccessibilityBridge()
    private let commandRouter: CommandRouter
    private var hotkeyManager: HotkeyManager?
    
    private var cancellables = Set<AnyCancellable>()
    private var isProcessingChunk = false  // Guard against concurrent chunk processing
    
    init() {
        self.commandRouter = CommandRouter(accessibilityBridge: accessibilityBridge)
        setupBindings()
        setupPermissions()
        
        // Setup router feedback
        commandRouter.onFeedback = { [weak self] message in
            self?.showError(message)
        }
    }
    
    private func setupBindings() {
        audioEngine.recordingCompletePublisher
            .sink { [weak self] audioData in
                self?.processAudioData(audioData)
            }
            .store(in: &cancellables)
        
        // Subscribe to audio chunks for continuous mode
        audioEngine.audioChunkPublisher
            .sink { [weak self] audioChunk in
                self?.processAudioChunk(audioChunk)
            }
            .store(in: &cancellables)
        
        whisperService.$transcriptionText
            .sink { [weak self] text in
                // Handle both empty and non-empty transcriptions
                self?.handleTranscriptionResult(text)
            }
            .store(in: &cancellables)
        
        whisperService.$error
            .sink { [weak self] error in
                if let error = error {
                    self?.handleError(error)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupPermissions() {
        Task {
            await MainActor.run {
                requestPermissions()
            }
        }
    }
    
    func setHotkeyManager(_ hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        
        hotkeyManager.commandHotkeyPressed
            .sink { [weak self] in
                print("📥 CommandManager: Received hotkey event - calling toggleCommandMode()")
                self?.toggleCommandMode()
            }
            .store(in: &cancellables)
    }
    
    private func requestPermissions() {
        audioEngine.requestMicrophonePermission { [weak self] granted in
            if !granted {
                self?.error = CommandError.microphonePermissionDenied
            }
        }
        
        // Note: Accessibility permission is now managed by VoiceControlApp using 
        // HotkeyManager.hasAccessibilityPermission() for reliable detection
    }
    
    func toggleCommandMode() {
        print("🎛️  CommandManager: toggleCommandMode called - isListening: \(isListening)")
        if isListening {
            print("   Stopping voice command...")
            stopVoiceCommand()
        } else {
            print("   Starting voice command...")
            if Config.continuousMode {
                startContinuousMode()
            } else {
                startVoiceCommand()
            }
        }
    }
    
    // MARK: - Public Methods for Manual Control
    
    func startVoiceCommand() {
        startListening()
    }
    
    func stopVoiceCommand() {
        stopListening()
        hudState = .idle
    }
    
    func startContinuousMode() {
        guard !isListening else { return }
        
        isContinuousMode = true
        isListening = true
        hudState = .continuousListening
        recognizedText = ""
        currentCommand = nil
        error = nil
        
        print("DEBUG: Starting continuous recording...")
        audioEngine.startContinuousRecording()
    }
    
    func stopContinuousMode() {
        isContinuousMode = false
        stopListening()
        hudState = .idle
    }
    
    func cancelCurrentOperation() {
        // Stop recording if active
        if isListening {
            if isContinuousMode {
                stopContinuousMode()
            } else {
                stopVoiceCommand()
            }
        }
        
        // Reset to idle state
        resetToIdle()
    }
    
    func retryLastCommand() {
        if !lastTranscription.isEmpty {
            hudState = .processing
            classifyAndExecute(lastTranscription)
        } else {
            startVoiceCommand()
        }
    }
    
    private func startListening() {
        guard !isListening else { 
            print("DEBUG: Already listening, ignoring start request")
            return 
        }
        
        // Ensure clean state before starting
        if hudState != .idle {
            print("DEBUG: Resetting from state \(hudState) to idle before starting")
            resetToIdle()
        }
        
        isListening = true
        hudState = .listening
        recognizedText = ""
        currentCommand = nil
        error = nil
        
        print("DEBUG: Starting audio recording...")
        audioEngine.startRecording()
    }
    
    private func stopListening() {
        guard isListening else { return }
        
        isListening = false
        audioEngine.stopRecording()
    }
    
    private func processAudioData(_ audioData: Data) {
        print("DEBUG: Processing audio data of size: \(audioData.count) bytes")
        hudState = .processing
        whisperService.startTranscription(audioData: audioData)
    }
    
    private func processAudioChunk(_ audioChunk: Data) {
        print("DEBUG: Processing audio chunk of size: \(audioChunk.count) bytes")
        
        // Don't process if we're already processing or in an error state
        guard hudState == .continuousListening else {
            print("DEBUG: Skipping chunk processing - current state: \(hudState)")
            return
        }
        
        // Guard against concurrent processing
        guard !isProcessingChunk else {
            print("DEBUG: Already processing a chunk, skipping")
            return
        }
        
        isProcessingChunk = true
        
        // Temporarily change state to processing while keeping continuous mode active
        hudState = .processing
        whisperService.startTranscription(audioData: audioChunk)
    }
    
    private func handleTranscriptionResult(_ text: String) {
        // Reset processing flag for continuous mode
        isProcessingChunk = false
        
        // Check if we got empty transcription
        if text.isEmpty {
            print("DEBUG: Received empty transcription")
            showError("No speech detected. Please try again.")
            return
        }
        
        // Set recognized text immediately to show in HUD
        recognizedText = text
        
        // Process non-empty transcription with LLM
        classifyAndExecute(text)
    }
    
    private func classifyAndExecute(_ text: String) {
        lastTranscription = text
        hudState = .classifying
        
        Task {
            do {
                let command = try await commandClassifier.classify(text)
                
                await MainActor.run {
                    self.currentCommand = command
                    
                    // Execute the command
                    Task {
                        do {
                            try await self.commandRouter.route(command)
                            
                            await MainActor.run {
                                if self.isContinuousMode {
                                    // Return to continuous listening after executing
                                    self.hudState = .continuousListening
                                    self.currentCommand = nil
                                    self.recognizedText = ""
                                } else {
                                    self.resetToIdle()
                                }
                            }
                        } catch {
                            await MainActor.run {
                                self.handleError(error)
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }
    
    
    
    private func resetToIdle() {
        hudState = .idle
        currentCommand = nil
        recognizedText = ""
        error = nil
        isListening = false  // Important: reset listening state
        
        // Stop audio engine if it's still running
        if audioEngine.isRecording {
            audioEngine.stopRecording()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.hudAnimationDuration) {
            // Clean up any remaining state
        }
    }
    
    private func showError(_ message: String) {
        let commandError = CommandError.executionFailed(message)
        error = commandError
        hudState = .error(commandError)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.isContinuousMode == true {
                self?.hudState = .continuousListening
                self?.error = nil
                // Clear recognized text after showing error
                self?.recognizedText = ""
            } else {
                self?.resetToIdle()
            }
        }
    }
    
    private func handleError(_ error: Error) {
        self.error = error
        hudState = .error(error)
        
        // Don't stop recording in continuous mode
        if !isContinuousMode && isListening {
            isListening = false
            audioEngine.stopRecording()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.isContinuousMode == true {
                self?.hudState = .continuousListening
                self?.error = nil
            } else {
                self?.resetToIdle()
            }
        }
    }
}

enum CommandError: LocalizedError {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case executionFailed(String)
    case noMatchingCommand
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied. Please enable in System Settings > Privacy & Security > Microphone."
        case .accessibilityPermissionDenied:
            return "Accessibility permission denied. Please enable in System Settings > Privacy & Security > Accessibility."
        case .executionFailed(let message):
            return "Command execution failed: \(message)"
        case .noMatchingCommand:
            return "No matching command found"
        }
    }
}