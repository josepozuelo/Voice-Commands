import Foundation
import Combine

class WhisperService: ObservableObject {
    @Published var transcriptionText = ""
    @Published var isTranscribing = false
    @Published var error: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private let session = URLSession.shared
    
    enum WhisperError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case transcriptionFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "OpenAI API key not found. Please set OPENAI_API_KEY environment variable."
            case .invalidResponse:
                return "Invalid response from OpenAI API"
            case .transcriptionFailed(let message):
                return "Transcription failed: \(message)"
            }
        }
    }
    
    func transcribe(audioData: Data) async throws -> String {
        guard !Config.openAIKey.isEmpty else {
            print("DEBUG: OpenAI API Key is empty!")
            throw WhisperError.noAPIKey
        }
        
        // Debug: Check API key format (only show first/last few chars for security)
        let key = Config.openAIKey
        if key.count > 10 {
            let prefix = String(key.prefix(7))
            let suffix = String(key.suffix(4))
            print("DEBUG: Using API Key: \(prefix)...\(suffix) (length: \(key.count))")
        }
        
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Config.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        let wavData = convertToWAV(audioData: audioData)
        print("DEBUG: Audio data size: \(audioData.count) bytes, WAV data size: \(wavData.count) bytes")
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
            print("DEBUG: Invalid response type")
            throw WhisperError.invalidResponse
        }
        
        // Debug output
        print("DEBUG: OpenAI API Response Status Code: \(httpResponse.statusCode)")
        
        // Log response body for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("DEBUG: OpenAI API Response Body: \(responseString)")
        }
        
        if httpResponse.statusCode != 200 {
            // Parse error response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("DEBUG: OpenAI API Error: \(message)")
                throw WhisperError.transcriptionFailed(message)
            } else {
                print("DEBUG: OpenAI API returned status code: \(httpResponse.statusCode)")
                throw WhisperError.invalidResponse
            }
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            print("DEBUG: Transcription successful: \(text)")
            return text
        } else {
            print("DEBUG: Failed to parse transcription response")
            throw WhisperError.transcriptionFailed("Could not parse response")
        }
    }
    
    func startTranscription(audioData: Data) {
        isTranscribing = true
        error = nil
        transcriptionText = "" // Reset previous transcription
        
        Task {
            do {
                let text = try await transcribe(audioData: audioData)
                await MainActor.run {
                    print("DEBUG: Setting transcription text to: '\(text)'")
                    self.transcriptionText = text
                    self.isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    print("DEBUG: WhisperService error: \(error)")
                    self.error = error
                    self.isTranscribing = false
                }
            }
        }
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