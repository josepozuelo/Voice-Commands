import Foundation
import os.log

private let logger = os.Logger(subsystem: "com.yourteam.VoiceControl", category: "CommandRouter")

class CommandRouter {
    private let accessibilityBridge: AccessibilityBridge
    private let gptService: GPTService
    
    // Callback for UI feedback
    var onFeedback: ((String) -> Void)?
    
    init(accessibilityBridge: AccessibilityBridge, gptService: GPTService = GPTService()) {
        self.accessibilityBridge = accessibilityBridge
        self.gptService = gptService
    }
    
    func route(_ command: CommandJSON) async throws {
        logger.info("Routing command: \(command.intent.rawValue)")
        
        switch command.intent {
        case .shortcut:
            try await routeShortcut(command)
            
        case .select:
            try await routeSelect(command)
            
        case .move:
            try await routeMove(command)
            
        case .tab:
            try await routeTab(command)
            
        case .overlay:
            try await routeOverlay(command)
            
        case .dictation:
            try await routeDictation(command)
            
        case .edit:
            try await routeEdit(command)
            
        case .highlight_phrase:
            try await routeHighlightPhrase(command)
            
        case .none:
            handleNoneIntent()
        }
    }
    
    // MARK: - Helper Methods
    
    private func constructKeyCommand(key: String, modifiers: UInt32) -> String {
        var parts: [String] = []
        
        if modifiers & 0x040000 != 0 { // Control
            parts.append("ctrl")
        }
        if modifiers & 0x080000 != 0 { // Option/Alt
            parts.append("option")
        }
        if modifiers & 0x020000 != 0 { // Shift
            parts.append("shift")
        }
        if modifiers & 0x100000 != 0 { // Command
            parts.append("cmd")
        }
        
        parts.append(key.lowercased())
        return parts.joined(separator: "+")
    }
    
    // MARK: - Shortcut Intent
    
    private func routeShortcut(_ command: CommandJSON) async throws {
        guard let key = command.key,
              let modifiers = command.modifiers else {
            throw RouteError.missingParameters("Shortcut requires key and modifiers")
        }
        
        logger.info("Executing shortcut: \(key) with modifiers: \(modifiers)")
        
        // Convert string modifiers to Carbon key codes
        var carbonModifiers: UInt32 = 0
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd":
                carbonModifiers |= 0x100000  // kCGEventFlagMaskCommand
            case "shift":
                carbonModifiers |= 0x020000  // kCGEventFlagMaskShift
            case "option", "opt", "alt":
                carbonModifiers |= 0x080000  // kCGEventFlagMaskAlternate
            case "control", "ctrl":
                carbonModifiers |= 0x040000  // kCGEventFlagMaskControl
            default:
                logger.warning("Unknown modifier: \(modifier)")
            }
        }
        
        // Execute shortcut
        let keyCommand = constructKeyCommand(key: key, modifiers: carbonModifiers)
        try accessibilityBridge.executeSystemAction(keyCommand)
    }
    
    // MARK: - Select Intent
    
    private func routeSelect(_ command: CommandJSON) async throws {
        guard let unit = command.unit else {
            throw RouteError.missingParameters("Select requires unit")
        }
        
        let direction = command.direction ?? .this
        let count = command.count ?? 1
        
        logger.info("Selecting \(count) \(unit.rawValue)(s) in direction: \(direction.rawValue)")
        
        // Map to existing selection types
        let selectionType: SelectionType
        switch unit {
        case .char:
            selectionType = .word // Character selection not directly supported, use word
        case .word:
            selectionType = .word
        case .sentence:
            selectionType = .sentence
        case .paragraph:
            selectionType = .paragraph
        case .line:
            selectionType = .line
        case .all:
            selectionType = .all
        }
        
        // Handle direction modifiers
        switch direction {
        case .this:
            // Select current unit
            try accessibilityBridge.selectText(matching: selectionType)
        case .next:
            // Select next unit(s)
            for _ in 0..<count {
                try accessibilityBridge.selectText(matching: selectionType)
                // TODO: Implement forward selection extension
            }
        case .prev:
            // Select previous unit(s)
            for _ in 0..<count {
                try accessibilityBridge.selectText(matching: selectionType)
                // TODO: Implement backward selection extension
            }
        default:
            logger.warning("Direction \(direction.rawValue) not supported for select")
            try accessibilityBridge.selectText(matching: selectionType)
        }
    }
    
    // MARK: - Move Intent
    
    private func routeMove(_ command: CommandJSON) async throws {
        guard let direction = command.direction,
              let unit = command.unit else {
            throw RouteError.missingParameters("Move requires direction and unit")
        }
        
        let count = command.count ?? 1
        
        logger.info("Moving \(count) \(unit.rawValue)(s) in direction: \(direction.rawValue)")
        
        // Map direction to cursor movement
        let cursorDirection: Direction
        switch direction {
        case .up:
            cursorDirection = .up
        case .down:
            cursorDirection = .down
        case .left, .back, .prev:
            cursorDirection = .left
        case .right, .forward, .next:
            cursorDirection = .right
        default:
            throw RouteError.unsupportedDirection(direction.rawValue)
        }
        
        // Map unit to cursor unit
        let cursorUnit: Unit
        switch unit {
        case .char:
            cursorUnit = .character
        case .word:
            cursorUnit = .word
        case .sentence:
            cursorUnit = .line // Sentence not directly supported for movement
        case .paragraph:
            cursorUnit = .paragraph
        case .line:
            cursorUnit = .line
        case .all:
            // Special handling for beginning/end of document
            if direction == .up || direction == .left || direction == .back {
                cursorUnit = .document
                try accessibilityBridge.moveCursor(to: .up, by: cursorUnit)
                return
            } else {
                cursorUnit = .document
                try accessibilityBridge.moveCursor(to: .down, by: cursorUnit)
                return
            }
        }
        
        // Execute move
        for _ in 0..<count {
            try accessibilityBridge.moveCursor(to: cursorDirection, by: cursorUnit)
        }
    }
    
    // MARK: - Tab Intent
    
    private func routeTab(_ command: CommandJSON) async throws {
        guard let action = command.action else {
            throw RouteError.missingParameters("Tab requires action")
        }
        
        logger.info("Tab action: \(action)")
        
        switch action {
        case "new":
            try accessibilityBridge.executeSystemAction("cmd+t")
        case "close":
            try accessibilityBridge.executeSystemAction("cmd+w")
        case "next":
            try accessibilityBridge.executeSystemAction("cmd+shift+]")
        case "prev":
            try accessibilityBridge.executeSystemAction("cmd+shift+[")
        case "show":
            if let index = command.index {
                // Command+1 through Command+9
                let key = String(index)
                try accessibilityBridge.executeSystemAction("cmd+\(key)")
            }
        default:
            throw RouteError.unsupportedAction(action)
        }
    }
    
    // MARK: - Placeholder Intents
    
    private func routeOverlay(_ command: CommandJSON) async throws {
        logger.info("Overlay intent not yet implemented")
        onFeedback?("Overlay commands coming soon")
    }
    
    private func routeDictation(_ command: CommandJSON) async throws {
        guard let text = command.text else {
            throw RouteError.missingParameters("Dictation requires text")
        }
        
        logger.info("Dictation intent: \"\(text)\"")
        onFeedback?("Dictation mode coming soon")
        // TODO: Implement dictation mode
    }
    
    private func routeEdit(_ command: CommandJSON) async throws {
        guard let instruction = command.instruction else {
            throw RouteError.missingParameters("Edit requires instruction")
        }
        
        logger.info("Edit intent: \"\(instruction)\"")
        onFeedback?("Edit mode coming soon")
        // TODO: Implement edit mode
    }
    
    // MARK: - Highlight Phrase Intent
    
    private func routeHighlightPhrase(_ command: CommandJSON) async throws {
        guard let userRequest = command.phrase else {
            throw RouteError.missingParameters("Highlight phrase requires phrase")
        }
        
        logger.info("Highlight phrase request: \"\(userRequest)\"")
        onFeedback?("Finding text...")
        
        do {
            // Step 1: Get the current text context
            let context = try accessibilityBridge.getEditContext()
            let contextText: String
            
            switch context {
            case .selectedText(let text):
                contextText = text
            case .paragraphAroundCursor(let text, _):
                contextText = text
            case .entireDocument(let text):
                contextText = text
            }
            
            logger.info("Got context text (length: \(contextText.count))")
            
            // Step 2: Use GPT to find the exact phrase in context
            let exactPhrase = try await gptService.findPhraseInContext(
                context: contextText,
                request: userRequest
            )
            
            if exactPhrase.isEmpty {
                throw RouteError.unsupportedAction("Phrase not found in text")
            }
            
            logger.info("GPT found phrase: \"\(exactPhrase)\"")
            
            // Step 3: Select the exact phrase
            try accessibilityBridge.selectPhrase(exactPhrase)
            onFeedback?("Selected: \(exactPhrase)")
            
        } catch {
            logger.error("Failed to highlight phrase: \(error)")
            onFeedback?("Phrase not found")
            throw error
        }
    }
    
    // MARK: - None Intent
    
    private func handleNoneIntent() {
        logger.info("No command detected")
        print("🔄 ROUTER: handleNoneIntent called - GPT returned intent='none'")
        print("🔄 ROUTER: Calling onFeedback with 'Please repeat your command'")
        onFeedback?("Please repeat your command")
    }
}

// MARK: - Errors

enum RouteError: LocalizedError {
    case missingParameters(String)
    case unsupportedDirection(String)
    case unsupportedAction(String)
    
    var errorDescription: String? {
        switch self {
        case .missingParameters(let details):
            return "Missing required parameters: \(details)"
        case .unsupportedDirection(let direction):
            return "Unsupported direction: \(direction)"
        case .unsupportedAction(let action):
            return "Unsupported action: \(action)"
        }
    }
}