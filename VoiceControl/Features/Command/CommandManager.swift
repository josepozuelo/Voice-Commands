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
            return 
        }
        
        // Ensure clean state before starting
        if hudState != .idle {
            resetToIdle()
        }
        
        isListening = true
        hudState = .listening
        recognizedText = ""
        currentCommand = nil
        error = nil
        
        audioEngine.startRecording()
    }
    
    private func stopListening() {
        guard isListening else { return }
        
        isListening = false
        audioEngine.stopRecording()
    }
    
    private func processAudioData(_ audioData: Data) {
        let seconds = Float(audioData.count) / (16000.0 * 4.0)
        print("🎵 COMMAND MANAGER: Received audio data: \(String(format: "%.1f", seconds))s")
        hudState = .processing
        whisperService.startTranscription(audioData: audioData)
    }
    
    private func processAudioChunk(_ audioChunk: Data) {
        
        // Don't process if we're already processing or in an error state
        guard hudState == .continuousListening else {
            return
        }
        
        // Temporarily change state to processing while keeping continuous mode active
        hudState = .processing
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
        recognizedText = text
        print("🎤 TRANSCRIPTION: Processing non-empty text: '\(text)'")
        
        // Process non-empty transcription with LLM
        classifyAndExecute(text)
    }
    
    private func classifyAndExecute(_ text: String) {
        print("📊 STATE: classifyAndExecute called with text: '\(text)'")
        lastTranscription = text
        hudState = .classifying
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
        print("❌ ERROR: showError called with message: '\(message)'")
        print("❌ ERROR: Called from router feedback callback")
        let commandError = CommandError.executionFailed(message)
        error = commandError
        hudState = .error(commandError)
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
    
    func setupHotkeyListener(hotkeyManager: HotkeyManager) {
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
            
        } catch {
            print("DEBUG: Edit Mode - Error: \(error)")
            handleError(error)
        }
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
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

struct EditModeHUD: View {
    @ObservedObject var editManager: EditManager
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            switch editManager.state {
            case .idle:
                EmptyView()
            case .selecting:
                selectingView
            case .recording(let startTime):
                recordingView(startTime: startTime)
            case .processing:
                processingView
            case .replacing:
                replacingView
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(hudPadding)
        .frame(minWidth: 350, maxWidth: Config.hudMaxWidth)
        .background(hudBackground)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: editManager.state)
    }
    
    // MARK: - State Views
    
    private var selectingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
            
            Text("Selecting text...")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    private func recordingView(startTime: Date) -> some View {
        HStack(spacing: 12) {
            animatedEditIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Mode")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !editManager.selectedText.isEmpty {
                    Text("Selected: \"\(String(editManager.selectedText.prefix(30)))\(editManager.selectedText.count > 30 ? "..." : "")\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text("Speak your edit instructions...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(formatTime(editManager.recordingTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Spacer()
            
            // Stop button
            Button(action: {
                editManager.stopEditing()
            }) {
                Image(systemName: "stop.fill")
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .help("Stop Recording (⌥⌘E)")
            
            // Cancel button
            Button(action: {
                editManager.cancelEditing()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
    }
    
    private var processingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Processing edit...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Applying your instructions to the text")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var replacingView: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            
            Text("Replacing text...")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    private func errorView(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: {
                editManager.cancelEditing()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
    }
    
    // MARK: - Components
    
    private var animatedEditIcon: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.8))
                .frame(width: 40, height: 40)
            
            Image(systemName: "pencil")
                .foregroundColor(.white)
                .font(.title2)
        }
        .rotationEffect(.degrees(editManager.state == .recording(startTime: Date()) ? 10 : 0))
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: editManager.recordingTime)
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Layout Properties
    
    private var hudPadding: EdgeInsets {
        EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
    }
    
    private var hudBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

class EditModeHUDWindowController: NSWindowController {
    private var editManager: EditManager
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init(editManager: EditManager) {
        self.editManager = editManager
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
        setupContent()
        observeEditManager()
        setupEscapeKeyMonitor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Start hidden
        window.orderOut(nil)
    }
    
    private func setupContent() {
        guard let window = window else { return }
        
        let contentView = EditModeHUD(editManager: editManager)
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    private func observeEditManager() {
        editManager.$state
            .sink { [weak self] state in
                DispatchQueue.main.async {
                    self?.updateWindowVisibility(for: state)
                    self?.positionWindow()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateWindowVisibility(for state: EditState) {
        guard let window = window else { return }
        
        switch state {
        case .idle:
            window.orderOut(nil)
        default:
            window.orderFrontRegardless()
        }
    }
    
    private func positionWindow() {
        guard let window = window,
              let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + Config.hudBottomMargin
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func setupEscapeKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                if self?.editManager.state != .idle {
                    self?.editManager.cancelEditing()
                    return nil // Consume the event
                }
            }
            return event
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}