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
        let systemPrompt = """
        Map a spoken phrase to exactly one JSON object from the list below and return only that JSON.
        If nothing matches, output {"intent":"none"}.
        
        { "intent":"shortcut", "key":"C", "modifiers":["command","shift"] }
        { "intent":"select",   "unit":"char|word|sentence|paragraph|line|all",
                                "direction":"this|next|prev", "count":1 }
        { "intent":"move",     "direction":"up|down|left|right|forward|back",
                                "unit":"char|word|sentence|paragraph|line|page|screen",
                                "count":1 }
        { "intent":"tab",      "action":"new|close|next|prev|show", "index":0 }
        { "intent":"overlay",  "action":"show|hide|click", "target":7 }
        { "intent":"dictation","text":"Hello, how are you?" }
        { "intent":"edit",     "instruction":"Replace the second sentence with 'Goodbye.'" }
        """
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript]
        ]
        
        let content = try await openAIService.chatCompletion(
            messages: messages,
            model: "gpt-4o-mini",
            temperature: 0,
            maxTokens: 150
        )
        
        guard let commandData = content.data(using: .utf8),
              let commandJSON = try? JSONDecoder().decode(CommandJSON.self, from: commandData) else {
            throw ClassificationError.noValidCommand
        }
        
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