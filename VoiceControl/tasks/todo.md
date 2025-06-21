# Voice Commands Todo List

## 1. Implement Continuous Voice Command Mode with Silence Detection

### Problem
Currently, voice commands require pressing the hotkey for each command. We want a continuous listening mode that automatically detects when the user has finished speaking and processes each command.

### Research Findings
- Whisper API works well with audio chunks as small as 0.5 seconds but 1-2 seconds is more reliable
- Silence detection typically uses: RMS threshold + duration (e.g., < 0.01 RMS for 0.5-1 second)
- OpenAI doesn't offer streaming transcription, but we can send chunks independently

### Solution

1. **Add configuration to Config.swift**
   ```swift
   static let continuousMode = true  // Toggle for continuous mode
   static let silenceRMSThreshold: Float = 0.01  // Audio level threshold for silence
   static let silenceDuration: TimeInterval = 0.8  // Duration of silence to trigger processing
   static let minAudioChunkDuration: TimeInterval = 0.5  // Minimum audio chunk size
   static let maxAudioChunkDuration: TimeInterval = 10.0  // Maximum before forced processing
   ```

2. **Update AudioEngine.swift**
   - Add silence detection logic using RMS values
   - Track silence duration with a timer
   - When silence detected:
     - Extract audio chunk from buffer
     - Send chunk via publisher
     - Clear processed audio from buffer
     - Continue recording for next chunk
   - Add max duration safety (force chunk at 10 seconds)

3. **Update CommandManager.swift**
   - Add continuous mode state management
   - Subscribe to audio chunks instead of complete recordings
   - Process each chunk independently:
     - Transcribe chunk
     - Match against commands
     - Execute or show disambiguation
   - Maintain continuous listening state until explicitly stopped

4. **Update CommandHUD.swift**
   - Show continuous mode indicator
   - Display "Listening..." continuously
   - Show processing state for each chunk
   - Add "Stop Continuous Mode" button

### Implementation Approach
- Start simple: Basic silence detection with fixed thresholds
- Test with different speaking patterns and environments
- Fine-tune thresholds based on testing
- Consider adaptive thresholds later if needed

---

## 2. Fix HUD Disambiguation with Continuous Voice Listening (Do After #1)

### Problem
1. Disambiguation picker disappears too quickly
2. Need voice selection without requiring another hotkey press

### Solution

1. **Add configuration to Config.swift**
   - Add `disambiguationTimeout: TimeInterval = 8.0`
   - Add `disambiguationListeningDelay: TimeInterval = 0.5` (brief delay before listening again)

2. **Update CommandManager.swift**
   - Add disambiguation timer (8 seconds)
   - When entering disambiguation state:
     - Show options
     - After 0.5s delay, automatically start listening again
     - Listen specifically for number utterances ("one", "two", "three", "1", "2", "3")
   - Add specialized number recognition during disambiguation
   - Cancel timer and stop listening when selection is made

3. **Update CommandHUD.swift**
   - Show listening indicator during disambiguation
   - Update hint text: "Say a number or click to select"
   - Keep Enter key support for first option
   - Visual feedback when listening for number

4. **Disambiguation flow**
   - User says command → Multiple matches found
   - HUD shows numbered options (1, 2, 3)
   - System automatically starts listening after brief pause
   - User simply says "one", "two", or "three"
   - System executes corresponding command
   - If no input within 8 seconds, dismiss HUD

This creates a seamless experience where users can immediately speak their selection without any additional interaction.

---

## Future Considerations
- Multi-chunk command reconstruction (if command spans multiple chunks)
- Adaptive silence thresholds based on ambient noise
- Voice activity detection (VAD) using more sophisticated algorithms
- Streaming transcription when/if OpenAI adds support