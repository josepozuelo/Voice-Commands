import Foundation
import Combine
import SwiftUI

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published private(set) var state: OverlayState = .collapsed
    @Published private(set) var recognizedText: String = ""
    @Published private(set) var errorMessage: String = ""
    @Published private(set) var isHovering: Bool = false
    @Published private(set) var amplitudeSamples: [Float] = []

    private let commandManager: CommandManager
    private let editManager: EditManager
    private let dictationManager: DictationManager

    private var cancellables = Set<AnyCancellable>()
    
    init(commandManager: CommandManager, editManager: EditManager, dictationManager: DictationManager) {
        self.commandManager = commandManager
        self.editManager = editManager
        self.dictationManager = dictationManager
        
        setupBindings()
    }
    
    // MARK: - Public Interface
    
    func handleHover(_ hovering: Bool) {
        guard state == .collapsed || state == .expanded else { return }
        isHovering = hovering
        state = hovering ? .expanded : .collapsed
    }
    
    func startCommand() {
        transition(to: .command(.listening))
        commandManager.startVoiceCommand()
    }
    
    func startEdit() {
        transition(to: .edit(.listening))
        editManager.startEditing()
    }
    
    func startDictation() {
        // Don't transition state here if already in dictation mode
        if case .dictation = state {
            // Already in dictation, toggle will submit it
        } else {
            transition(to: .dictation(.listening))
        }
        Task {
            await dictationManager.toggleDictation()
        }
    }
    
    func stop() {
        switch state {
        case .command:
            commandManager.stopVoiceCommand()
        case .edit:
            editManager.cancelEditing()
        case .dictation:
            Task {
                await dictationManager.cancelDictation()
            }
        default:
            break
        }
        transition(to: .collapsed)
    }
    
    // MARK: - Private Methods
    
    private func transition(to newState: OverlayState) {
        withAnimation(.easeInOut(duration: 0.2)) {
            state = newState
        }
    }
    
    private func setupBindings() {
        // Observe CommandManager state changes
        commandManager.$hudState
            .sink { [weak self] hudState in
                guard let self = self else { return }
                switch hudState {
                case .idle:
                    if case .command = self.state {
                        self.transition(to: .collapsed)
                    }
                case .listening:
                    self.transition(to: .command(.listening))
                case .continuousListening:
                    self.transition(to: .command(.continuousListening))
                case .processing:
                    self.transition(to: .command(.processing))
                case .classifying:
                    self.transition(to: .command(.classifying))
                case .error(let error):
                    self.errorMessage = error.localizedDescription
                    self.transition(to: .command(.error(error.localizedDescription)))
                }
            }
            .store(in: &cancellables)
        
        // Observe CommandManager recognized text
        commandManager.$recognizedText
            .sink { [weak self] text in
                self?.recognizedText = text
            }
            .store(in: &cancellables)
        
        // Observe EditManager state changes
        editManager.$state
            .sink { [weak self] editState in
                guard let self = self else { return }
                switch editState {
                case .idle:
                    if case .edit = self.state {
                        self.transition(to: .collapsed)
                    }
                case .selecting, .recording:
                    self.transition(to: .edit(.listening))
                case .processing:
                    self.transition(to: .edit(.processing))
                case .replacing:
                    self.transition(to: .edit(.replacing))
                case .error(let message):
                    self.errorMessage = message
                    self.transition(to: .edit(.error(message)))
                }
            }
            .store(in: &cancellables)
        
        // Observe DictationManager state changes
        dictationManager.$state
            .sink { [weak self] dictationState in
                guard let self = self else { return }
                switch dictationState {
                case .idle:
                    if case .dictation = self.state {
                        self.transition(to: .collapsed)
                    }
                case .recording:
                    self.transition(to: .dictation(.listening))
                case .processing:
                    self.transition(to: .dictation(.processing))
                case .error(let message):
                    self.errorMessage = message
                    self.transition(to: .dictation(.error(message)))
                }
            }
            .store(in: &cancellables)

        // Observe DictationManager amplitude samples for waveform
        dictationManager.$amplitudeSamples
            .sink { [weak self] samples in
                self?.amplitudeSamples = samples
            }
            .store(in: &cancellables)
        
        // Handle mode switching notifications
        NotificationCenter.default.publisher(for: .startEditMode)
            .sink { [weak self] _ in
                self?.startEdit()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .startDictationMode)
            .sink { [weak self] _ in
                self?.startDictation()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .resumeContinuousMode)
            .sink { [weak self] _ in
                self?.startCommand()
            }
            .store(in: &cancellables)
    }
}