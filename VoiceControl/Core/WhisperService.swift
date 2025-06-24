import Foundation
import Combine

// MARK: - OpenAIError
enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case requestFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not found. Please set OPENAI_API_KEY environment variable."
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        }
    }
}

// MARK: - OpenAIService
class OpenAIService {
    private let session = URLSession.shared
    
    private var apiKey: String {
        Config.openAIKey
    }
    
    func transcribeAudio(audioData: Data) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        let wavData = convertToWAV(audioData: audioData)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Config.whisperModel)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.requestFailed(message)
            } else {
                throw OpenAIError.invalidResponse
            }
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text
        } else {
            throw OpenAIError.requestFailed("Could not parse response")
        }
    }
    
    func chatCompletion(messages: [[String: String]], 
                       model: String = Config.EditMode.gptModel,
                       temperature: Double = Config.EditMode.gptTemperature,
                       maxTokens: Int = Config.EditMode.gptMaxTokens) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.noAPIKey
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw OpenAIError.requestFailed(message)
            } else {
                throw OpenAIError.invalidResponse
            }
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: OpenAIService.chatCompletion - Model: \(model), Response: '\(trimmedContent)'")
        
        return trimmedContent
    }
    
    private func convertToWAV(audioData: Data) -> Data {
        let pcmData = audioData
        let sampleRate: Int32 = Int32(Config.audioSampleRate)
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 32
        let byteRate = sampleRate * Int32(numChannels) * Int32(bitsPerSample) / 8
        let blockAlign = numChannels * bitsPerSample / 8
        let dataSize = Int32(pcmData.count)
        
        var header = Data()
        
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: Int32(36 + dataSize).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: Int16(3).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        return header + pcmData
    }
}

// MARK: - GPTService
class GPTService {
    private let openAIService: OpenAIService
    
    init(openAIService: OpenAIService = OpenAIService()) {
        self.openAIService = openAIService
    }
    
    func editText(originalText: String, instructions: String) async throws -> String {
        print("DEBUG: GPTService.editText - Original text: '\(originalText)'")
        print("DEBUG: GPTService.editText - Instructions: '\(instructions)'")
        
        let systemPrompt = """
        Dictation Error Corrector Prompt (string-friendly)

        You receive two strings:
            •	ORIGINAL – raw speech-to-text.
            •	EDITS – spoken correction commands that were also transcribed and may contain typos or homophone errors.

        Return ONE line of JSON:

        {"corrected_message":"<the fixed text>"}


        ⸻

        How to read EDITS

        Phrase in EDITS	What it really means
        “change X to Y”, “replace X with Y”	X = word in ORIGINAL that sounds like X; Y = intended replacement (interpret both phonetically).
        X not spelled the same in ORIGINAL	Choose the closest phonetic or obvious misspelling (“wrold” for “world”, etc.).
        Homophones (their/there, two/too, etc.)	Use sentence context to pick the correct one.


        ⸻

        Special workflow for names
            1.	Locate – Find the NAME in ORIGINAL that most closely sounds like the name referenced in EDITS.
            2.	Spell – Parse the speaker’s spelled-out letters:
            •	Speech-to-text may transcribe letters as words (“B” → “be”, “R” → “are”).
            •	Re-assemble those letters into the intended spelling.
            3.	Replace – Substitute that corrected spelling into ORIGINAL.
            •	Never copy-paste the name string from EDITS without validating the spelling you inferred.

        ⸻

        Do apply
            •	Only the specific corrections requested (after smart interpretation).

        Do NOT
            •	Touch punctuation, capitalization, or anything else unless explicitly told.
            •	Add or delete content outside the pinpointed change.
        """
        
        let userPrompt = """
        Original message: "\(originalText)"
        
        Edit prompt: "\(instructions)"
        """
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        
        let response = try await openAIService.chatCompletion(
            messages: messages,
            model: Config.EditMode.gptModel,
            temperature: Config.EditMode.gptTemperature,
            maxTokens: Config.EditMode.gptMaxTokens
        )
        
        print("DEBUG: GPTService.editText - Raw GPT response: '\(response)'")
        
        // Parse JSON response
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let correctedMessage = json["corrected_message"] as? String {
            print("DEBUG: GPTService.editText - Parsed corrected message: '\(correctedMessage)'")
            return correctedMessage
        }
        
        // If JSON parsing fails, try to extract the text between quotes
        if let range = response.range(of: #""corrected_message":\s*"([^"]*)"#, options: .regularExpression) {
            let match = String(response[range])
            if let textRange = match.range(of: #":\s*"([^"]*)"#, options: .regularExpression) {
                let text = String(match[textRange])
                    .replacingOccurrences(of: #":\s*""#, with: "", options: .regularExpression)
                    .dropLast() // Remove trailing quote
                print("DEBUG: GPTService.editText - Extracted corrected message via regex: '\(text)'")
                return String(text)
            }
        }
        
        print("DEBUG: GPTService.editText - Failed to parse response, throwing error")
        // If all parsing fails, return the original text
        throw OpenAIError.invalidResponse
    }
    
    func formatDictation(_ text: String) async throws -> String {
        guard Config.EditMode.formatDictation else {
            return text
        }
        
        let systemPrompt = """
        You are a helpful assistant that lightly formats dictated text. Your task is to:
        • Add appropriate punctuation and capitalization
        • Fix obvious spelling errors from speech recognition
        • Split run-on sentences appropriately
        • Do NOT change the meaning, style, or substance of the text
        • Do NOT add or remove content
        • Return only the formatted text, nothing else
        """
        
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]
        
        let response = try await openAIService.chatCompletion(
            messages: messages,
            model: Config.EditMode.gptModel,
            temperature: 0.1, // Very low temperature for consistent formatting
            maxTokens: text.count * 2 // Allow some room for punctuation
        )
        
        print("DEBUG: GPTService.formatDictation - Input: '\(text)'")
        print("DEBUG: GPTService.formatDictation - GPT response: '\(response)'")
        
        return response
    }
}

// MARK: - WhisperService
class WhisperService: ObservableObject {
    @Published var transcriptionText = ""
    @Published var isTranscribing = false
    @Published var error: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private let openAIService: OpenAIService
    
    init(openAIService: OpenAIService = OpenAIService()) {
        self.openAIService = openAIService
    }
    
    func transcribe(audioData: Data) async throws -> String {
        do {
            let text = try await openAIService.transcribeAudio(audioData: audioData)
            return text
        } catch {
            throw error
        }
    }
    
    func startTranscription(audioData: Data) {
        print("🎙️ WHISPER: startTranscription called with audio data: \(audioData.count) bytes")
        isTranscribing = true
        error = nil
        // Don't reset transcriptionText here - it causes a race condition
        // The empty string triggers handleTranscriptionResult before actual transcription completes
        
        Task {
            do {
                print("🎙️ WHISPER: Calling transcribe...")
                let text = try await transcribe(audioData: audioData)
                print("🎙️ WHISPER: Transcription result: '\(text)'")
                await MainActor.run {
                    self.transcriptionText = text
                    self.isTranscribing = false
                }
            } catch {
                print("🎙️ WHISPER: Transcription error: \(error)")
                await MainActor.run {
                    self.error = error
                    self.isTranscribing = false
                }
            }
        }
    }
}