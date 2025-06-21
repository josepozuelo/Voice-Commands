import Foundation
import CoreGraphics

struct Config {
    static let dictationHotkey = "⌥⌘D"
    static let editHotkey = "⌥⌘E"
    static let commandHotkey = "⌃⇧V"
    
    static let openAIKey: String = {
        // For development: First try environment variable
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        
        // For production: Read from Info.plist (configured via xcconfig)
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String, !bundleKey.isEmpty {
            return bundleKey
        }
        
        // Fallback to config file in app support directory (for user-provided keys)
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configURL = appSupportURL.appendingPathComponent("VoiceControl/config.json")
        
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apiKey = json["openai_api_key"] as? String {
            return apiKey
        }
        
        return ""
    }()
    static let whisperModel = "whisper-1"
    static let gptModel = "gpt-4-turbo-preview"
    
    static let silenceThreshold: TimeInterval = 1.0
    static let fuzzyMatchThreshold: Double = 0.85
    
    // Continuous Mode Configuration
    static let continuousMode = true  // Toggle for continuous mode
    static let silenceRMSThreshold: Float = 0.01  // Audio level threshold for silence
    static let silenceDuration: TimeInterval = 0.8  // Duration of silence to trigger processing
    static let minAudioChunkDuration: TimeInterval = 0.5  // Minimum audio chunk size
    static let maxAudioChunkDuration: TimeInterval = 10.0  // Maximum before forced processing
    
    // Disambiguation Configuration
    static let disambiguationTimeout: TimeInterval = 8.0  // Time before dismissing disambiguation
    static let disambiguationListeningDelay: TimeInterval = 0.5  // Brief delay before listening again
    
    static let hudBottomMargin: CGFloat = 20
    static let hudMaxWidth: CGFloat = 600
    static let hudAnimationDuration: TimeInterval = 0.2
    
    static let audioSampleRate: Double = 16000
    static let audioBufferSize: Int = 1024
    
    enum HotkeyCode {
        // Key codes from Carbon framework: kVK_ANSI_C = 0x08, kVK_ANSI_D = 0x02, kVK_ANSI_E = 0x0E
        // Modifiers are no longer used since we check for Command and Option individually
        static let controlShiftV: (keyCode: UInt16, modifiers: UInt32) = (0x09, 0x020100)
        static let optionCommandD: (keyCode: UInt16, modifiers: UInt32) = (0x02, 0x180000)
        static let optionCommandE: (keyCode: UInt16, modifiers: UInt32) = (0x0E, 0x180000)
    }
}