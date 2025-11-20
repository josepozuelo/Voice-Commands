import Foundation
import Combine
import SwiftUI

extension Notification.Name {
    static let startEditMode = Notification.Name("startEditMode")
    static let startDictationMode = Notification.Name("startDictationMode")
    static let resumeContinuousMode = Notification.Name("resumeContinuousMode")
}

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
        
        // Listen for resume continuous mode notification
        NotificationCenter.default.publisher(for: .resumeContinuousMode)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("📥 CommandManager: Received resumeContinuousMode notification")
                print("   Current isContinuousMode: \(self.isContinuousMode)")
                print("   Current isListening: \(self.isListening)")
                
                // Always trust the notification - DictationManager knows best
                print("   ✅ Resuming continuous mode after dictation/edit")
                self.startContinuousMode()
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
            print("   Stopping continuous mode...")
            stopContinuousMode()
        } else {
            print("   Starting continuous mode...")
            startContinuousMode()
        }
    }

    // MARK: - Public Methods for Manual Control
    
    func startContinuousMode() {
        guard !isListening else { return }
        
        DispatchQueue.main.async {
            self.isContinuousMode = true
            self.isListening = true
            self.hudState = .continuousListening
            self.recognizedText = ""
            self.currentCommand = nil
            self.error = nil
        }
        
        audioEngine.startContinuousRecording()
    }
    
    func stopContinuousMode() {
        DispatchQueue.main.async {
            self.isContinuousMode = false
            self.hudState = .idle
        }
        stopListening()
    }
    
    func cancelCurrentOperation() {
        // Stop recording if active
        if isListening {
            stopContinuousMode()
        }

        // Reset to idle state
        resetToIdle()
    }
    
    func retryLastCommand() {
        if !lastTranscription.isEmpty {
            DispatchQueue.main.async {
                self.hudState = .processing
            }
            classifyAndExecute(lastTranscription)
        } else {
            startContinuousMode()
        }
    }
    
    private func stopListening() {
        guard isListening else { return }

        DispatchQueue.main.async {
            self.isListening = false
        }
        audioEngine.stopRecording()
    }
    
    private func processAudioChunk(_ audioChunk: Data) {
        
        // Don't process if we're already processing or in an error state
        guard hudState == .continuousListening else {
            return
        }
        
        // Temporarily change state to processing while keeping continuous mode active
        DispatchQueue.main.async {
            self.hudState = .processing
        }
        whisperService.startTranscription(audioData: audioChunk)
    }
    
    private func handleTranscriptionResult(_ text: String) {
        print("🎤 TRANSCRIPTION: Received result: '\(text)' (length: \(text.count))")
        
        // Check if we got empty transcription
        if text.isEmpty {
            print("🎤 TRANSCRIPTION: Empty result, showing error")
            showError("No speech detected. Please try again.")
            return
        }
        
        // Set recognized text immediately to show in HUD
        DispatchQueue.main.async {
            self.recognizedText = text
        }
        print("🎤 TRANSCRIPTION: Processing non-empty text: '\(text)'")
        
        // Process non-empty transcription with LLM
        classifyAndExecute(text)
    }
    
    private func classifyAndExecute(_ text: String) {
        print("📊 STATE: classifyAndExecute called with text: '\(text)'")
        lastTranscription = text
        DispatchQueue.main.async {
            self.hudState = .classifying
        }
        print("📊 STATE: Changed to .classifying")
        
        Task {
            do {
                print("📊 STATE: About to call commandClassifier.classify()")
                let command = try await commandClassifier.classify(text)
                print("📊 STATE: Received command with intent: \(command.intent.rawValue)")
                
                await MainActor.run {
                    self.currentCommand = command
                    
                    // Execute the command
                    Task {
                        do {
                            print("📊 STATE: About to route command")
                            try await self.commandRouter.route(command)
                            print("📊 STATE: Command routed successfully")
                            
                            await MainActor.run {
                                if self.isContinuousMode {
                                    // Return to continuous listening after executing
                                    print("📊 STATE: Returning to continuous mode")
                                    self.hudState = .continuousListening
                                    self.currentCommand = nil
                                    self.recognizedText = ""
                                } else {
                                    print("📊 STATE: Resetting to idle")
                                    self.resetToIdle()
                                }
                            }
                        } catch {
                            print("📊 STATE: Error routing command: \(error)")
                            await MainActor.run {
                                self.handleError(error)
                            }
                        }
                    }
                }
            } catch {
                print("📊 STATE: Error classifying: \(error)")
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }
    
    
    
    private func resetToIdle() {
        DispatchQueue.main.async {
            self.hudState = .idle
            self.currentCommand = nil
            self.recognizedText = ""
            self.error = nil
            self.isListening = false  // Important: reset listening state
        }
        
        // Stop audio engine if it's still running
        if audioEngine.isRecording {
            audioEngine.stopRecording()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.hudAnimationDuration) {
            // Clean up any remaining state
        }
    }
    
    private func showError(_ message: String) {
        print("❌ ERROR: showError called with message: '\(message)'")
        print("❌ ERROR: Called from router feedback callback")
        let commandError = CommandError.executionFailed(message)
        DispatchQueue.main.async {
            self.error = commandError
            self.hudState = .error(commandError)
        }
        print("❌ ERROR: HUD state changed to .error")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.isContinuousMode == true {
                print("❌ ERROR: Returning to continuous mode after error")
                self?.hudState = .continuousListening
                self?.error = nil
                // Clear recognized text after showing error
                self?.recognizedText = ""
            } else {
                print("❌ ERROR: Resetting to idle after error")
                self?.resetToIdle()
            }
        }
    }
    
    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.error = error
            self.hudState = .error(error)
        }
        
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

// MARK: - EditMode Support

enum EditState: Equatable {
    case idle
    case selecting
    case recording(startTime: Date)
    case processing
    case replacing
    case error(String)
}

@MainActor
class EditManager: ObservableObject {
    @Published private(set) var state: EditState = .idle
    @Published private(set) var selectedText: String = ""
    @Published private(set) var recordingTime: TimeInterval = 0
    @Published private(set) var errorMessage: String = ""
    
    private let audioEngine: AudioEngine
    private let whisperService: WhisperService
    private let accessibilityBridge: AccessibilityBridge
    private let gptService: GPTService
    
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var editContext: EditContext?
    
    // Track if continuous mode should be resumed after edit
    private var shouldResumeContinuousMode = false
    
    weak var commandManager: CommandManager?
    
    init(audioEngine: AudioEngine,
         whisperService: WhisperService,
         accessibilityBridge: AccessibilityBridge,
         gptService: GPTService) {
        self.audioEngine = audioEngine
        self.whisperService = whisperService
        self.accessibilityBridge = accessibilityBridge
        self.gptService = gptService
        
        setupBindings()
    }
    
    private func setupBindings() {
        audioEngine.$isRecording
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if !isRecording && self.state != .idle {
                    if case .recording = self.state {
                        Task {
                            await self.processEditInstructions()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func setupHotkeyListener(hotkeyManager: HotkeyManager, commandManager: CommandManager) {
        // Connect Edit Mode hotkey
        hotkeyManager.editHotkeyPressed
            .sink { [weak self] in
                self?.startEditing()
            }
            .store(in: &cancellables)
        
        // Connect Edit Mode button from HUD
        NotificationCenter.default.publisher(for: .startEditMode)
            .sink { [weak self] _ in
                self?.startEditing()
            }
            .store(in: &cancellables)
    }
    
    func startEditing() {
        // Toggle behavior: if recording, stop it
        if case .recording = state {
            Task {
                await audioEngine.stopRecording()
            }
            return
        }
        
        guard state == .idle else { return }
        
        // Check if continuous mode is currently active
        shouldResumeContinuousMode = commandManager?.isContinuousMode ?? false
        print("✏️ EditManager: Starting edit mode")
        print("   CommandManager continuous mode: \(commandManager?.isContinuousMode ?? false)")
        print("   Should resume continuous mode: \(shouldResumeContinuousMode)")
        
        Task {
            do {
                state = .selecting
                
                print("DEBUG: EditManager - Getting edit context")
                let context = try accessibilityBridge.getEditContext()
                editContext = context
                
                // Extract text based on context
                switch context {
                case .selectedText(let text):
                    print("DEBUG: EditManager - Editing selected text: '\(text)'")
                    selectedText = text
                    
                case .paragraphAroundCursor(let text, _):
                    print("DEBUG: EditManager - Editing paragraph around cursor: '\(text)'")
                    selectedText = text
                    
                case .entireDocument(let text):
                    print("DEBUG: EditManager - Editing entire document")
                    selectedText = text
                }
                
                recordingStartTime = Date()
                state = .recording(startTime: recordingStartTime!)
                startRecordingTimer()
                
                try await audioEngine.startRecording(
                    enableSilenceDetection: false,
                    maxDuration: Config.EditMode.maxRecordingDuration
                )
                
            } catch {
                print("DEBUG: EditManager - Error in startEditing: \(error)")
                handleError(error)
            }
        }
    }
    
    func stopEditing() {
        guard case .recording = state else { return }
        
        Task {
            await audioEngine.stopRecording()
        }
    }
    
    func cancelEditing() {
        stopRecordingTimer()
        recordingStartTime = nil
        selectedText = ""
        editContext = nil
        state = .idle
        
        Task {
            await audioEngine.stopRecording()
        }
        
        // Return to continuous mode if it was active before
        if shouldResumeContinuousMode {
            print("✏️ EditManager: Posting resumeContinuousMode notification (cancel)")
            NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
            shouldResumeContinuousMode = false
        } else {
            print("✏️ EditManager: Not resuming continuous mode (was not active before)")
        }
    }
    
    private func processEditInstructions() async {
        stopRecordingTimer()
        state = .processing
        
        do {
            guard let audioData = await audioEngine.getRecordedAudio() else {
                throw EditError.noAudioRecorded
            }
            
            let transcription = try await whisperService.transcribe(audioData: audioData)
            print("DEBUG: Edit Mode - Transcription: '\(transcription)'")
            
            guard !transcription.isEmpty else {
                throw EditError.emptyTranscription
            }
            
            print("DEBUG: Edit Mode - Sending to GPT with original text: '\(selectedText)'")
            let editedText = try await gptService.editText(
                originalText: selectedText,
                instructions: transcription
            )
            print("DEBUG: Edit Mode - GPT response: '\(editedText)'")
            
            state = .replacing
            
            // Use the new direct AX replacement method with context
            print("DEBUG: Edit Mode - Attempting direct AX replacement")
            print("DEBUG: Edit Mode - Edit context: \(String(describing: editContext))")
            try accessibilityBridge.replaceSelectionWithCorrectedText(editedText, editContext: editContext)
            print("DEBUG: Edit Mode - Text replacement successful")
            
            state = .idle
            resetState()
            
            // Return to continuous mode if it was active before
            if shouldResumeContinuousMode {
                print("✏️ EditManager: Posting resumeContinuousMode notification (after successful edit)")
                NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
                shouldResumeContinuousMode = false
            } else {
                print("✏️ EditManager: Not resuming continuous mode (was not active before)")
            }
            
        } catch {
            print("DEBUG: Edit Mode - Error: \(error)")
            handleError(error)
        }
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let startTime = self.recordingStartTime else { return }
                
                self.recordingTime = Date().timeIntervalSince(startTime)
                
                if self.recordingTime >= Config.EditMode.maxRecordingDuration {
                    self.stopEditing()
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingTime = 0
    }
    
    private func resetState() {
        selectedText = ""
        editContext = nil
        recordingStartTime = nil
        errorMessage = ""
    }
    
    private func handleError(_ error: Error) {
        stopRecordingTimer()
        
        let message: String
        if let editError = error as? EditError {
            message = editError.localizedDescription
        } else {
            message = error.localizedDescription
        }
        
        errorMessage = message
        state = .error(message)
        
        Task {
            await audioEngine.stopRecording()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.state = .idle
            self?.resetState()
            
            // Return to continuous mode if it was active before, even after error
            if self?.shouldResumeContinuousMode == true {
                print("✏️ EditManager: Posting resumeContinuousMode notification (after error)")
                NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
                self?.shouldResumeContinuousMode = false
            }
        }
    }
}

enum EditError: LocalizedError {
    case noTextFieldAccessible
    case noAudioRecorded
    case emptyTranscription
    case replacementFailed
    
    var errorDescription: String? {
        switch self {
        case .noTextFieldAccessible:
            return "No accessible text field found"
        case .noAudioRecorded:
            return "No audio was recorded"
        case .emptyTranscription:
            return "Could not transcribe any speech"
        case .replacementFailed:
            return "Failed to replace the text"
        }
    }
}