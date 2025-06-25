import Foundation
import Combine

class CommandClassifier: ObservableObject {
    @Published var classificationResult: CommandJSON?
    @Published var isClassifying = false
    @Published var error: Error?
    
    private let openAIService: OpenAIService
    
    init(openAIService: OpenAIService = OpenAIService()) {
        self.openAIService = openAIService
    }
    
    enum ClassificationError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case classificationFailed(String)
        case noValidCommand
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not found. Please set OPENAI_API_KEY environment variable."
            case .invalidResponse:
                return "Invalid response from OpenAI API"
            case .classificationFailed(let message):
                return "Classification failed: \(message)"
            case .noValidCommand:
                return "No valid command detected"
            }
        }
    }
    
    func classify(_ transcript: String) async throws -> CommandJSON {
        print("🤖 GPT CALL - CommandClassifier.classify() called with transcript: '\(transcript)'")
        print("🤖 GPT CALL - Timestamp: \(Date())")
        
        let systemPrompt = """
        Map a spoken phrase to exactly one JSON object from the list below and return only that JSON.
        If nothing matches, output {"intent":"none"}.
        The user will speak in normal regular language, you should decipher it and extract specific intents from it.
        The user is on macOS.

        SHORTCUT INTENT - For keyboard shortcuts and system navigation:
        { "intent":"shortcut", "key":"C", "modifiers":["command","shift"] }
        Examples: copy (cmd+C), paste (cmd+V), undo (cmd+Z), save (cmd+S), find (cmd+F),
        switch apps (cmd+tab), switch windows (cmd+`), minimize window (cmd+M), 
        close window (cmd+W), hide app (cmd+H), quit app (cmd+Q),
        mission control/explode view (ctrl+up), show desktop (F11), spotlight (cmd+space),
        next desktop/space (ctrl+right), previous desktop/space (ctrl+left),
        screenshot (cmd+shift+4), force quit (cmd+option+escape),
        page up (pageup), page down (pagedown), go to top (cmd+up), go to bottom (cmd+down),
        go to end of page (pagedown), go to top of page (pageup)
        
        IMPORTANT: For arrow keys use "up", "down", "left", "right" (not "uparrow" or "arrow")

        SELECT INTENT - For text selection:
        { "intent":"select",   "unit":"char|word|sentence|paragraph|line|all",
                                "direction":"this|next|prev", "count":1 }

        MOVE INTENT - For cursor movement:
        { "intent":"move",     "direction":"up|down|left|right|forward|back|beginning|end",
                                "unit":"char|word|sentence|paragraph|line",
                                "count":1 }
        Note: For page navigation use shortcut intent with pageup/pagedown keys
        Examples: go to beginning of paragraph, move to end of line, go to start of document

        TAB INTENT - For browser tab management only:
        { "intent":"tab",      "action":"new|close|next|prev|show", "index":0 }
        Examples: new tab, close tab, next tab, previous tab, go to tab 3

        OVERLAY INTENT:
        { "intent":"overlay",  "action":"show|hide|click", "target":7 }

        DICTATION INTENT:
        { "intent":"dictation","text":"Hello, how are you?" }

        EDIT INTENT:
        { "intent":"edit",     "instruction":"Replace the second sentence with 'Goodbye.'" }
        
        HIGHLIGHT_PHRASE INTENT - For selecting specific text:
        { "intent":"highlight_phrase", "phrase":"example text" }
        Examples: highlight the word example, select the phrase hello world, 
        highlight configuration, select John Smith
        
        MODE_SWITCH INTENT - For switching between input modes:
        { "intent":"mode_switch", "mode":"dictation|edit|command" }
        Examples: 
        - "start dictation", "dictation mode", "begin dictating" → mode: "dictation"
        - "edit mode", "start editing", "edit text" → mode: "edit"
        - "command mode", "back to commands" → mode: "command"
        """
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript]
        ]
        
        print("🤖 GPT CALL - Sending to OpenAI API...")
        let content = try await openAIService.chatCompletion(
            messages: messages,
            model: Config.gptModel,
            temperature: 0,
            maxTokens: 150
        )
        print("🤖 GPT CALL - Received response from OpenAI")
        
        print("DEBUG: CommandClassifier - Input: '\(transcript)'")
        print("DEBUG: CommandClassifier - GPT response: '\(content)'")
        
        guard let commandData = content.data(using: .utf8),
              let commandJSON = try? JSONDecoder().decode(CommandJSON.self, from: commandData) else {
            print("DEBUG: CommandClassifier - Failed to parse GPT response as CommandJSON")
            throw ClassificationError.noValidCommand
        }
        
        print("DEBUG: CommandClassifier - Parsed command: intent=\(commandJSON.intent)")
        
        return commandJSON
    }
    
    func classifyTranscript(_ transcript: String) {
        isClassifying = true
        error = nil
        
        Task {
            do {
                let result = try await classify(transcript)
                await MainActor.run {
                    self.classificationResult = result
                    self.isClassifying = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isClassifying = false
                }
            }
        }
    }
}