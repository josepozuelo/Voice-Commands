import Foundation
import Combine
import SwiftUI

enum HUDState: Equatable {
    case idle
    case listening
    case processing
    case disambiguating
    case error(Error)
    
    static func == (lhs: HUDState, rhs: HUDState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.processing, .processing), (.disambiguating, .disambiguating):
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
    @Published var currentMatches: [CommandMatch] = []
    @Published var error: Error?
    @Published var lastTranscription = ""
    
    private let audioEngine = AudioEngine()
    private let whisperService = WhisperService()
    private let commandMatcher = CommandMatcher()
    private let accessibilityBridge = AccessibilityBridge()
    private var hotkeyManager: HotkeyManager?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        setupPermissions()
    }
    
    private func setupBindings() {
        audioEngine.recordingCompletePublisher
            .sink { [weak self] audioData in
                self?.processAudioData(audioData)
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
            startVoiceCommand()
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
    
    func retryLastCommand() {
        if !lastTranscription.isEmpty {
            hudState = .processing
            handleTranscription(lastTranscription)
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
        currentMatches = []
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
    
    private func handleTranscriptionResult(_ text: String) {
        // Check if we got empty transcription
        if text.isEmpty {
            print("DEBUG: Received empty transcription")
            showError("No speech detected. Please try again.")
            return
        }
        
        // Process non-empty transcription
        handleTranscription(text)
    }
    
    private func handleTranscription(_ text: String) {
        recognizedText = text
        lastTranscription = text
        
        let matches = commandMatcher.findMatches(for: text)
        currentMatches = Array(matches.prefix(3))
        
        if let bestMatch = matches.first {
            if bestMatch.confidence >= Config.fuzzyMatchThreshold {
                executeCommand(bestMatch.command)
                resetToIdle()
            } else if matches.count > 1 {
                showDisambiguation()
            } else {
                showError("No matching command found for: \"\(text)\"")
            }
        } else {
            showError("No matching command found for: \"\(text)\"")
        }
    }
    
    private func showDisambiguation() {
        hudState = .disambiguating
    }
    
    func selectMatch(at index: Int) {
        guard index < currentMatches.count else { return }
        
        let selectedMatch = currentMatches[index]
        executeCommand(selectedMatch.command)
        resetToIdle()
    }
    
    private func executeCommand(_ command: Command) {
        do {
            switch command.action {
            case .selectText(let selectionType):
                try accessibilityBridge.selectText(matching: selectionType)
                
            case .moveCursor(let direction, let unit):
                try accessibilityBridge.moveCursor(to: direction, by: unit)
                
            case .systemAction(let keyCommand):
                try accessibilityBridge.executeSystemAction(keyCommand)
                
            case .appCommand(let appId, let command):
                // Future implementation for app-specific commands
                print("App command not yet implemented: \(appId) - \(command)")
            }
        } catch {
            handleError(error)
        }
    }
    
    private func resetToIdle() {
        hudState = .idle
        currentMatches = []
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.resetToIdle()
        }
    }
    
    private func handleError(_ error: Error) {
        self.error = error
        hudState = .error(error)
        
        // Ensure we're not stuck in listening state
        if isListening {
            isListening = false
            audioEngine.stopRecording()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.resetToIdle()
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