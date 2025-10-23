import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        Group {
            switch viewModel.state {
            case .collapsed:
                collapsedView
            case .expanded:
                expandedView
            case .command(let phase):
                commandView(phase: phase)
            case .edit(let phase):
                editView(phase: phase)
            case .dictation(let phase):
                dictationView(phase: phase)
            }
        }
        .padding(8)
        .background(backgroundView)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .onHover { hovering in
            viewModel.handleHover(hovering)
        }
    }
    
    // MARK: - Collapsed State
    
    private var collapsedView: some View {
        Image(systemName: "waveform.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.primary.opacity(0.6))
            .frame(width: 40, height: 40)
    }
    
    // MARK: - Expanded State
    
    private var expandedView: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.primary.opacity(0.6))
            
            HStack(spacing: 8) {
                ModeButton(icon: "mic.fill") {
                    viewModel.startCommand()
                }
                .help("Voice Command (⌃J)")
                
                ModeButton(icon: "pencil") {
                    viewModel.startEdit()
                }
                .help("Edit Mode (⌃L)")
                
                ModeButton(icon: "text.append") {
                    viewModel.startDictation()
                }
                .help("Dictation Mode (⌃K)")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 200, height: 50)
    }
    
    // MARK: - Command Mode
    
    private func commandView(phase: OverlayState.CommandPhase) -> some View {
        HStack(spacing: 12) {
            commandIcon(for: phase)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(commandTitle(for: phase))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if !viewModel.recognizedText.isEmpty {
                    Text(viewModel.recognizedText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: viewModel.stop) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 250, maxWidth: 400, minHeight: 60)
    }
    
    // MARK: - Edit Mode
    
    private func editView(phase: OverlayState.EditPhase) -> some View {
        HStack(spacing: 12) {
            editIcon(for: phase)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(editTitle(for: phase))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if case .error(let message) = phase {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Button(action: viewModel.stop) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 250, maxWidth: 400, minHeight: 60)
    }
    
    // MARK: - Dictation Mode

    private func dictationView(phase: OverlayState.DictationPhase) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                dictationIcon(for: phase)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dictationTitle(for: phase))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)

                    if case .error(let message) = phase {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button(action: viewModel.stop) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Waveform visualization when recording
            if case .listening = phase, !viewModel.amplitudeSamples.isEmpty {
                WaveformView(amplitudes: viewModel.amplitudeSamples)
                    .frame(height: 40)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 250, maxWidth: 400)
    }
    
    // MARK: - Helper Views
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: viewModel.state.isActive ? 12 : 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: viewModel.state.isActive ? 12 : 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
    
    // MARK: - Icons
    
    private func commandIcon(for phase: OverlayState.CommandPhase) -> some View {
        Group {
            switch phase {
            case .listening, .continuousListening:
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: phase == .continuousListening ? "infinity" : "mic.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                }
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(1.2)
                        .opacity(0.5)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: true)
                )
            case .processing, .classifying:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 36)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func editIcon(for phase: OverlayState.EditPhase) -> some View {
        Group {
            switch phase {
            case .listening:
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                }
            case .processing, .replacing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 36)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func dictationIcon(for phase: OverlayState.DictationPhase) -> some View {
        Group {
            switch phase {
            case .listening:
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "text.append")
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                }
            case .processing:
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.8)
                    .frame(width: 36, height: 36)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Titles
    
    private func commandTitle(for phase: OverlayState.CommandPhase) -> String {
        switch phase {
        case .listening:
            return "Listening..."
        case .continuousListening:
            return "Continuous Mode"
        case .processing:
            return "Processing..."
        case .classifying:
            return "Classifying command..."
        case .error:
            return "Error"
        }
    }
    
    private func editTitle(for phase: OverlayState.EditPhase) -> String {
        switch phase {
        case .listening:
            return "Describe your edit..."
        case .processing:
            return "Processing edit..."
        case .replacing:
            return "Applying changes..."
        case .error:
            return "Error"
        }
    }
    
    private func dictationTitle(for phase: OverlayState.DictationPhase) -> String {
        switch phase {
        case .listening:
            return "Dictating..."
        case .processing:
            return "Processing..."
        case .error:
            return "Error"
        }
    }
}