import Foundation
import Combine
import SwiftUI

enum DictationState: Equatable {
    case idle
    case recording(startTime: Date)
    case processing
    case error(String)
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
            if case .recording = state {
                await stopDictation()
                return
            }
            
            do {
                _ = try accessibilityBridge.getEditContext()
            } catch {
                state = .error("No text field found. Please click in a text field first.")
                showHUD = true
                return
            }
            
            state = .recording(startTime: Date())
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
    
    func stopDictation() async {
        await audioEngine.stopRecording()
        if case .recording = state {
            await processDictation()
        }
    }
    
    func cancelDictation() async {
        await audioEngine.stopRecording()
        state = .idle
        showHUD = false
        
        // Return to continuous mode if it was active before
        NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
    }
    
    private func processDictation() async {
        state = .processing
        
        do {
            guard let audioData = await audioEngine.getRecordedAudio() else {
                throw NSError(domain: "DictationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio recorded"])
            }
            
            var transcribedText = try await whisperService.transcribe(audioData: audioData)
            
            if Config.DictationMode.formatWithGPT {
                transcribedText = try await gptService.formatDictation(transcribedText)
            }
            
            try accessibilityBridge.insertTextAtCursor(transcribedText)
            
            state = .idle
            showHUD = false
            
            // Return to continuous mode if it was active before
            NotificationCenter.default.post(name: .resumeContinuousMode, object: nil)
        } catch {
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
                
                TimeElapsedView(startTime: startTime)
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
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 40, height: 40)
            
            Image(systemName: "mic.fill")
                .foregroundColor(.white)
                .font(.system(size: 20))
        }
        .scaleEffect(1.1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: true)
    }
}

struct TimeElapsedView: View {
    let startTime: Date
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        Text(formatTime(elapsedTime))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.8))
            .onAppear {
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    DispatchQueue.main.async {
                        elapsedTime = Date().timeIntervalSince(startTime)
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    await self?.manager.cancelDictation()
                }
                return nil
            }
            return event
        }
    }
}