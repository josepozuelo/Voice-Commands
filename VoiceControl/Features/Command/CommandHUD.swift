import SwiftUI
import Combine

extension Notification.Name {
    static let startEditMode = Notification.Name("startEditMode")
    static let startDictationMode = Notification.Name("startDictationMode")
    static let resumeContinuousMode = Notification.Name("resumeContinuousMode")
}

struct CommandHUD: View {
    @ObservedObject var commandManager: CommandManager
    @State private var selectedIndex = 0
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            switch commandManager.hudState {
            case .idle:
                idleStateView
            case .listening:
                listeningView
            case .continuousListening:
                continuousListeningView
            case .processing:
                processingView
            case .classifying:
                classifyingView
            case .error(let error):
                errorView(error)
            }
        }
        .padding(hudPadding)
        .frame(minWidth: minWidth, maxWidth: maxWidth)
        .background(hudBackground)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .scaleEffect(scaleEffect)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: commandManager.hudState)
    }
    
    // MARK: - State Views
    
    private var idleStateView: some View {
        HStack(spacing: 12) {
            // App Icon/Logo
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text("VoiceControl")
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Dictation Mode button
            Button(action: {
                NotificationCenter.default.post(name: .startDictationMode, object: nil)
            }) {
                Label("Dictation", systemImage: "text.append")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
            .help("Dictation Mode (⌃K)")
            
            // Edit Mode button
            Button(action: {
                NotificationCenter.default.post(name: .startEditMode, object: nil)
            }) {
                Label("Edit", systemImage: "pencil")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
            .help("Edit Mode (⌃L)")
            
            // Manual trigger button
            Button(action: {
                commandManager.startVoiceCommand()
            }) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.accentColor))
                    .scaleEffect(isHovering ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
            .help("Start Voice Command (⌃J)")
        }
    }
    
    private var listeningView: some View {
        HStack(spacing: 12) {
            animatedMicrophoneIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Listening...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !commandManager.recognizedText.isEmpty {
                    Text(commandManager.recognizedText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Stop button
            Button(action: {
                commandManager.stopVoiceCommand()
            }) {
                Image(systemName: "stop.fill")
                    .font(.body)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .help("Stop Listening")
        }
    }
    
    private var continuousListeningView: some View {
        HStack(spacing: 12) {
            continuousModeIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Continuous Mode")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !commandManager.recognizedText.isEmpty {
                    Text("\"\(commandManager.recognizedText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Listening for commands...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Stop continuous mode button
            Button(action: {
                commandManager.stopContinuousMode()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Stop Continuous Mode")
        }
    }
    
    private var processingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Processing...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !commandManager.recognizedText.isEmpty {
                    Text("\"\(commandManager.recognizedText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
    }
    
    private var classifyingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Classifying command...")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                
                Button(action: {
                    commandManager.stopVoiceCommand()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
            
            if !commandManager.recognizedText.isEmpty {
                Text("Heard: \"\(commandManager.recognizedText)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }
            
            if let command = commandManager.currentCommand {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    
                    Text("Intent: \(command.intent.rawValue.capitalized)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    
    private func errorView(_ error: Error) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !commandManager.recognizedText.isEmpty {
                    Text("Heard: \"\(commandManager.recognizedText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Retry button
            Button(action: {
                commandManager.retryLastCommand()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.orange))
            }
            .buttonStyle(.plain)
            .help("Retry")
        }
    }
    
    // MARK: - Components
    
    private var animatedMicrophoneIcon: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.8))
                .frame(width: 40, height: 40)
            
            Image(systemName: "mic.fill")
                .foregroundColor(.white)
                .font(.title2)
        }
        .scaleEffect(commandManager.isListening ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: commandManager.isListening)
    }
    
    private var continuousModeIcon: some View {
        ZStack {
            // Pulsing circles to indicate continuous listening
            Circle()
                .stroke(Color.green.opacity(0.3), lineWidth: 2)
                .frame(width: 50, height: 50)
                .scaleEffect(1.2)
                .opacity(0.5)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: true)
            
            Circle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 40, height: 40)
            
            Image(systemName: "infinity")
                .foregroundColor(.white)
                .font(.title2)
        }
    }
    
    // MARK: - Layout Properties
    
    private var hudPadding: EdgeInsets {
        switch commandManager.hudState {
        case .idle:
            return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        default:
            return EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        }
    }
    
    private var minWidth: CGFloat {
        switch commandManager.hudState {
        case .idle:
            return 350
        default:
            return 350
        }
    }
    
    private var maxWidth: CGFloat {
        switch commandManager.hudState {
        case .idle:
            return 400
        default:
            return Config.hudMaxWidth
        }
    }
    
    private var hudBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
    
    private var scaleEffect: CGFloat {
        switch commandManager.hudState {
        case .idle:
            return 0.95
        default:
            return 1.0
        }
    }
}

struct CommandHUDWindow: NSViewRepresentable {
    @ObservedObject var commandManager: CommandManager
    
    func makeNSView(context: Context) -> NSView {
        let hostingView = NSHostingView(rootView: CommandHUD(commandManager: commandManager))
        return hostingView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Updates will be handled by SwiftUI automatically
    }
}

class CommandHUDWindowController: NSWindowController {
    private var commandManager: CommandManager
    private var eventMonitor: Any?
    
    init(commandManager: CommandManager) {
        self.commandManager = commandManager
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
        setupContent()
        observeCommandManager()
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
        
        // Always show the window
        window.orderFrontRegardless()
        positionWindow()
    }
    
    private func setupContent() {
        guard let window = window else { return }
        
        let contentView = CommandHUDWindow(commandManager: commandManager)
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    private func observeCommandManager() {
        commandManager.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateWindowSize()
                self?.positionWindow()
            }
        }
        .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func updateWindowSize() {
        guard let window = window else { return }
        
        // Adjust window size based on state
        let targetSize: NSSize
        switch commandManager.hudState {
        case .idle:
            targetSize = NSSize(width: 400, height: 60)
        case .listening, .processing:
            targetSize = NSSize(width: 400, height: 80)
        case .continuousListening:
            targetSize = NSSize(width: 400, height: 80)
        case .classifying:
            targetSize = NSSize(width: 500, height: 140)
        case .error:
            targetSize = NSSize(width: 500, height: 100)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.hudAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(origin: window.frame.origin, size: targetSize),
                display: true
            )
        }
    }
    
    private func positionWindow() {
        guard let window = window,
              let screen = NSScreen.main else { 
            print("Warning: Unable to position window - window or screen is nil")
            return 
        }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + Config.hudBottomMargin
        
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func setupEscapeKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 is the key code for Escape
                if self?.commandManager.hudState != .idle {
                    self?.commandManager.cancelCurrentOperation()
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