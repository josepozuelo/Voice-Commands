import Foundation

struct CommandJSON: Codable {
    let intent: CommandIntent
    
    let key: String?
    let modifiers: [String]?
    
    let unit: SelectionUnit?
    let direction: CommandDirection?
    let count: Int?
    
    let action: String?
    let index: Int?
    
    let target: Int?
    
    let text: String?
    
    let instruction: String?
    
    let phrase: String?
}

enum CommandIntent: String, Codable {
    case shortcut
    case select
    case move
    case tab
    case overlay
    case dictation
    case edit
    case highlight_phrase
    case none
}

enum SelectionUnit: String, Codable {
    case char
    case word
    case sentence
    case paragraph
    case line
    case all
}

enum CommandDirection: String, Codable {
    case this
    case next
    case prev
    case up
    case down
    case left
    case right
    case forward
    case back
}

enum TabAction: String, Codable {
    case new
    case close
    case next
    case prev
    case show
}

enum OverlayAction: String, Codable {
    case show
    case hide
    case click
}

extension CommandJSON {
    var isValidShortcut: Bool {
        guard intent == .shortcut else { return false }
        return key != nil && modifiers != nil
    }
    
    var isValidSelect: Bool {
        guard intent == .select else { return false }
        return unit != nil
    }
    
    var isValidMove: Bool {
        guard intent == .move else { return false }
        return direction != nil && unit != nil
    }
    
    var isValidTab: Bool {
        guard intent == .tab else { return false }
        return action != nil
    }
    
    var isValidOverlay: Bool {
        guard intent == .overlay else { return false }
        return action != nil
    }
    
    var isValidDictation: Bool {
        guard intent == .dictation else { return false }
        return text != nil && !text!.isEmpty
    }
    
    var isValidEdit: Bool {
        guard intent == .edit else { return false }
        return instruction != nil && !instruction!.isEmpty
    }
    
    var isValidHighlightPhrase: Bool {
        guard intent == .highlight_phrase else { return false }
        return phrase != nil && !phrase!.isEmpty
    }
    
    var isValid: Bool {
        switch intent {
        case .shortcut:
            return isValidShortcut
        case .select:
            return isValidSelect
        case .move:
            return isValidMove
        case .tab:
            return isValidTab
        case .overlay:
            return isValidOverlay
        case .dictation:
            return isValidDictation
        case .edit:
            return isValidEdit
        case .highlight_phrase:
            return isValidHighlightPhrase
        case .none:
            return true
        }
    }
}