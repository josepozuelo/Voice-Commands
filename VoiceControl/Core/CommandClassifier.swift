import Foundation
import Combine

class CommandClassifier: ObservableObject {
    @Published var classificationResult: CommandJSON?
    @Published var isClassifying = false
    @Published var error: Error?
    
    private let session = URLSession.shared
    
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
        guard !Config.openAIKey.isEmpty else {
            throw ClassificationError.noAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Config.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript]
            ],
            "temperature": 0,
            "max_tokens": 150
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClassificationError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClassificationError.classificationFailed(message)
            } else {
                throw ClassificationError.invalidResponse
            }
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClassificationError.invalidResponse
        }
        
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let commandData = trimmedContent.data(using: .utf8),
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