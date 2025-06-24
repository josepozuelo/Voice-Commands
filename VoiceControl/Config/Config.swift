import Foundation
import CoreGraphics

struct Config {
    static let dictationHotkey = "⌥⌘D"
    static let editHotkey = "⌥⌘E"
    static let commandHotkey = "⌃⇧V"
    
    // Edit Mode Configuration
    struct EditMode {
        static let maxRecordingDuration: TimeInterval = 600.0  // 10 minutes max recording
        static let autoSelectParagraph = true  // Auto-select paragraph if no selection
        static let gptModel = "gpt-4.1-mini-2025-04-14"  // GPT model for text editing
        static let gptTemperature = 0.3  // Low temperature for consistent edits
        static let gptMaxTokens = 2000  // Max tokens for response
        static let formatDictation = true  // Flag to format dictated text with GPT
    }
    
    static let openAIKey: String = {
        // For development: First try environment variable
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            print("🔑 Config: Using OpenAI API key from environment variable")
            return envKey
        }
        
        // For production: Read from Info.plist (configured via xcconfig)
        if let bundleKey = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String {
            if !bundleKey.isEmpty {
                print("🔑 Config: Using OpenAI API key from Info.plist")
                return bundleKey
            } else {
                print("⚠️ Config: Found empty OpenAI API key in Info.plist")
            }
        } else {
            print("⚠️ Config: No OpenAI API key found in Info.plist")
        }
        
        // Fallback to config file in app support directory (for user-provided keys)
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configURL = appSupportURL.appendingPathComponent("VoiceControl/config.json")
        
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let apiKey = json["openai_api_key"] as? String {
            print("🔑 Config: Using OpenAI API key from config.json")
            return apiKey
        }
        
        print("❌ Config: No OpenAI API key found in any location!")
        return ""
    }()
    static let whisperModel = "whisper-1"
    static let gptModel = "gpt-4.1-mini-2025-04-14"
    
    static let silenceThreshold: TimeInterval = 1.0
    static let fuzzyMatchThreshold: Double = 0.85
    
    // Continuous Mode Configuration
    static let continuousMode = true  // Toggle for continuous mode
    static let minAudioChunkDuration: TimeInterval = 0.5  // Minimum audio chunk size
    static let maxAudioChunkDuration: TimeInterval = 10.0  // Maximum before forced processing
    
    
    // WebRTC VAD Configuration  
    static let vadEnabled = true  // Always use WebRTC Voice Activity Detection
    static let vadMode: Int32 = 1  // VAD aggressiveness (0-3, 1 = slightly aggressive)
    static let vadFrameDuration: TimeInterval = 0.02  // 20ms frames
    static let vadSampleRate: Int = 16000  // VAD requires 16kHz
    static let vadFrameSamples: Int = 320  // 320 samples per 20ms frame at 16kHz
    static let vadSpeechFrameThreshold = 3  // Consecutive speech frames to start speech
    static let vadSilenceTimeout: TimeInterval = 1.2  // Not used - Silero VAD uses frame counts instead
    static let vadMinSpeechDuration: TimeInterval = 0.2  // Minimum speech duration to process
    
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