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
        // No bindings needed - we'll process when stopDictation is called
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

struct DictationModeHUD: View {
    @ObservedObject var manager: DictationManager
    
    var body: some View {
        VStack(spacing: 16) {
            header
            
            switch manager.state {
            case .idle:
                EmptyView()
            case .recording(let startTime):
                recordingView(startTime: startTime)
            case .processing:
                processingView
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
        .frame(width: 380)
    }
    
    private var header: some View {
        HStack {
            Image(systemName: "mic.fill")
                .foregroundColor(.white)
                .font(.system(size: 20))
            
            Text("Dictation Mode")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            if case .recording = manager.state {
                Button(action: {
                    Task {
                        await manager.cancelDictation()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private func recordingView(startTime: Date) -> some View {
        VStack(spacing: 12) {
            HStack {
                recordingIndicator

                Text("Recording...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)

                Spacer()
            }

            Button(action: {
                Task {
                    await manager.stopDictation()
                }
            }) {
                HStack {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                    Text("Stop Recording")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.8))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())

            Text("Press ⌃K to stop")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private var processingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            
            Text("Processing dictation...")
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 16))
                
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineLimit(3)
            }
            
            Button(action: {
                manager.resetState()
            }) {
                Text("Dismiss")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var recordingIndicator: some View {
        RecordingIndicator()
    }
}

struct RecordingIndicator: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 40, height: 40)

            Image(systemName: "mic.fill")
                .foregroundColor(.white)
                .font(.system(size: 20))
        }
    }
}

class DictationModeHUDWindowController: NSWindowController {
    private let manager: DictationManager
    private var escapeMonitor: Any?
    
    init(manager: DictationManager) {
        self.manager = manager
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: DictationModeHUD(manager: manager))
        
        super.init(window: window)
        
        positionWindow()
        setupEscapeKeyMonitoring()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let windowSize = window?.frame.size ?? .zero
        
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + 100
        
        window?.setFrame(NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height), display: true)
    }
    
    private func setupEscapeKeyMonitoring() {
        // Use global monitor so escape works even when window doesn't have focus
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    await self?.manager.cancelDictation()
                }
            }
        }
    }
}