import Foundation

enum OverlayState: Equatable {
    // Presentation states
    case collapsed                // 40×40 pill
    case expanded                 // 200×50 on hover
    
    // Active voice modes with their own sub-state
    case command(CommandPhase)
    case edit(EditPhase)
    case dictation(DictationPhase)
    
    enum CommandPhase: Equatable {
        case listening
        case continuousListening
        case processing
        case classifying
        case error(String)
    }
    
    enum EditPhase: Equatable {
        case listening
        case processing
        case replacing
        case error(String)
    }
    
    enum DictationPhase: Equatable {
        case listening
        case processing
        case error(String)
    }
    
    // Helper computed properties
    var isActive: Bool {
        switch self {
        case .collapsed, .expanded:
            return false
        case .command, .edit, .dictation:
            return true
        }
    }
    
    var isError: Bool {
        switch self {
        case .command(.error), .edit(.error), .dictation(.error):
            return true
        default:
            return false
        }
    }
}