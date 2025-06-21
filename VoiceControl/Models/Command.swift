import Foundation

struct Command: Codable, Identifiable {
    let id: String
    let phrases: [String]
    let action: CommandAction
    let category: CommandCategory
}

enum CommandAction: Codable {
    case selectText(SelectionType)
    case moveCursor(Direction, Unit)
    case systemAction(String)
    case appCommand(appId: String, command: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case selectionType
        case direction
        case unit
        case key
        case appId
        case command
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "selectText":
            let selectionType = try container.decode(SelectionType.self, forKey: .selectionType)
            self = .selectText(selectionType)
        case "moveCursor":
            let direction = try container.decode(Direction.self, forKey: .direction)
            let unit = try container.decode(Unit.self, forKey: .unit)
            self = .moveCursor(direction, unit)
        case "systemAction":
            let key = try container.decode(String.self, forKey: .key)
            self = .systemAction(key)
        case "appCommand":
            let appId = try container.decode(String.self, forKey: .appId)
            let command = try container.decode(String.self, forKey: .command)
            self = .appCommand(appId: appId, command: command)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Invalid action type")
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .selectText(let selectionType):
            try container.encode("selectText", forKey: .type)
            try container.encode(selectionType, forKey: .selectionType)
        case .moveCursor(let direction, let unit):
            try container.encode("moveCursor", forKey: .type)
            try container.encode(direction, forKey: .direction)
            try container.encode(unit, forKey: .unit)
        case .systemAction(let key):
            try container.encode("systemAction", forKey: .type)
            try container.encode(key, forKey: .key)
        case .appCommand(let appId, let command):
            try container.encode("appCommand", forKey: .type)
            try container.encode(appId, forKey: .appId)
            try container.encode(command, forKey: .command)
        }
    }
}

enum SelectionType: String, Codable {
    case word
    case sentence
    case paragraph
    case line
    case all
    case nextWord
    case previousWord
    case nextSentence
    case previousSentence
    case nextParagraph
    case previousParagraph
    case toEndOfLine
    case toStartOfLine
    case toEndOfDocument
    case toStartOfDocument
    case lastWord
    case lastSentence
    case lastParagraph
}

enum Direction: String, Codable {
    case left
    case right
    case up
    case down
    case beginning
    case end
}

enum Unit: String, Codable {
    case character
    case word
    case line
    case paragraph
    case document
}

enum CommandCategory: String, Codable {
    case textSelection
    case navigation
    case editing
    case system
    case application
}

struct CommandList: Codable {
    let commands: [Command]
}