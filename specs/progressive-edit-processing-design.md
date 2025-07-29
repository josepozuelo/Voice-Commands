# Progressive Edit Processing Design Specification

## Overview

This document outlines the design for implementing progressive edit processing in VoiceControl's Edit Mode. The goal is to reduce perceived latency by beginning transcription and processing while the user is still recording, without compromising accuracy or losing context.

## Current State

### Current Edit Mode Flow
1. User presses `⌥⌘E` to start edit mode
2. System begins recording audio (no silence detection)
3. User speaks their edit instructions
4. User presses `⌥⌘E` again to stop recording
5. System sends entire audio buffer to Whisper
6. System sends transcription to GPT-4 for edit processing
7. System replaces selected text with edited version

### Current Issues
- **Latency**: User waits for full transcription + GPT processing after stopping
- **No feedback**: No indication of progress during recording
- **All-or-nothing**: Entire recording must complete before any processing

## Proposed Solution

### Progressive Processing Pipeline

```
Recording Timeline:
|-------- User Speaking --------|-- Thinking --|-- Speaking --|-- Stop --|
|-- Chunk 1 --|-- Chunk 2 --|-- Chunk 3 --|-- Chunk 4 --|-- Final --|

Processing Timeline:
              |-- Whisper 1 --|
                           |-- Whisper 2 --|
                                        |-- Whisper 3 --|
                                                     |-- Whisper 4 --|
                                                                  |-- GPT --|
```

### Key Design Principles

1. **Intelligent Chunking**: Use VAD to detect speech segments without stopping recording
2. **Progressive Transcription**: Send completed speech segments to Whisper while recording continues
3. **Context Preservation**: Maintain full audio buffer and all transcriptions for final GPT processing
4. **Minimum Chunk Size**: Ensure chunks are large enough for accurate Whisper transcription
5. **User Feedback**: Show real-time transcription progress in the UI

## Implementation Design

### 1. Audio Chunking Strategy

```swift
class ProgressiveEditChunker {
    // Configuration
    static let minChunkDuration: TimeInterval = 2.0  // Minimum 2s for Whisper accuracy
    static let maxChunkDuration: TimeInterval = 10.0 // Force chunk after 10s
    static let silenceThreshold: TimeInterval = 1.0  // 1s silence triggers chunk
    
    // State
    private var currentChunk = Data()
    private var chunkStartTime = Date()
    private var lastSpeechTime = Date()
    private var isInSpeech = false
    
    // Callbacks
    var onChunkReady: ((Data) -> Void)?
    var onSpeechDetected: (() -> Void)?
}
```

### 2. Progressive Transcription Manager

```swift
class ProgressiveTranscriptionManager {
    private var transcriptionQueue = DispatchQueue(label: "transcription.queue")
    private var transcribedChunks: [TranscriptionChunk] = []
    private var pendingTranscriptions: Set<UUID> = []
    
    struct TranscriptionChunk {
        let id = UUID()
        let audioData: Data
        let startTime: TimeInterval
        let endTime: TimeInterval
        var transcription: String?
        var isProcessing = false
    }
    
    func processChunk(_ audioData: Data, startTime: TimeInterval, endTime: TimeInterval) {
        // Queue chunk for transcription
        // Update UI with processing status
        // Maintain order for final assembly
    }
    
    func assembleFinalTranscription() -> String {
        // Combine all chunks in order
        // Handle any pending transcriptions
        // Return complete instruction text
    }
}
```

### 3. Edit Mode State Machine

```swift
enum ProgressiveEditState {
    case idle
    case selecting
    case recording(chunks: [TranscriptionChunk])
    case waitingForSpeech
    case processingSpeech(chunkId: UUID)
    case finalizingTranscription
    case processingEdit
    case replacing
    case error(String)
}
```

### 4. UI Updates

```swift
struct EditModeHUD {
    // Real-time feedback
    @Published var transcribedText: String = ""
    @Published var isTranscribing: Bool = false
    @Published var chunksProcessed: Int = 0
    @Published var estimatedCompletion: TimeInterval?
    
    // Visual indicators
    var showLiveTranscription: Bool = true
    var showProcessingIndicator: Bool = true
}
```

## Technical Implementation Details

### Audio Processing Flow

1. **VAD Integration for Chunking (not stopping)**:
   ```swift
   // Modified VADSilenceDetector for edit mode
   class EditModeVADChunker: VADSilenceDetector {
       override func voiceEnded(withWavData wavData: Data!) {
           // Don't stop recording, just emit chunk
           if currentAudioChunk.count >= minChunkSize {
               onChunkReady?(currentAudioChunk)
               currentAudioChunk = Data() // Reset for next chunk
           }
           // Continue recording...
       }
   }
   ```

2. **Chunk Size Management**:
   - Minimum chunk: 2 seconds (for Whisper accuracy)
   - Maximum chunk: 10 seconds (to prevent memory issues)
   - Silence-triggered chunks: After 1 second of silence
   - Force chunk on maximum duration even if speaking

3. **Parallel Processing**:
   ```swift
   func processChunkAsync(_ chunk: Data) {
       Task {
           // Send to Whisper immediately
           let transcription = try await whisperService.transcribe(chunk)
           
           // Update UI with partial transcription
           await MainActor.run {
               self.updatePartialTranscription(transcription)
           }
           
           // Store for final assembly
           transcriptionManager.addTranscription(transcription, for: chunk.id)
       }
   }
   ```

### Memory Management

1. **Dual Buffer System**:
   - Active chunk buffer (current speech segment)
   - Complete recording buffer (full context)
   
2. **Chunk Lifecycle**:
   - Create chunk when speech detected
   - Send chunk when silence detected or max duration reached
   - Clear chunk buffer after sending
   - Maintain reference in transcription manager

### Error Handling

1. **Partial Failure Recovery**:
   - If a chunk fails to transcribe, mark as failed
   - Continue with other chunks
   - On final assembly, retry failed chunks or skip

2. **Network Resilience**:
   - Queue chunks locally if network unavailable
   - Process in order when connection restored
   - Show offline indicator in UI

## API Changes

### AudioEngine Extensions

```swift
extension AudioEngine {
    func startProgressiveRecording(
        chunkCallback: @escaping (Data) -> Void,
        maxDuration: TimeInterval
    ) async throws {
        // Initialize progressive chunker
        // Set up chunk emission callback
        // Start recording with chunking enabled
    }
}
```

### WhisperService Updates

```swift
extension WhisperService {
    func transcribeChunk(
        _ audioData: Data,
        previousContext: String? = nil
    ) async throws -> String {
        // Include previous context for better accuracy
        // Return transcription with chunk metadata
    }
}
```

### EditManager Modifications

```swift
extension EditManager {
    private func setupProgressiveProcessing() {
        progressiveChunker.onChunkReady = { [weak self] chunk in
            self?.processChunkAsync(chunk)
        }
        
        // UI updates
        transcriptionManager.onTranscriptionUpdate = { [weak self] partial in
            self?.updateLiveTranscription(partial)
        }
    }
}
```

## Performance Considerations

### Chunk Size vs. Accuracy Trade-offs

| Chunk Size | Whisper Accuracy | Latency | Recommendation |
|------------|------------------|---------|----------------|
| < 1s       | Poor (60-70%)    | Excellent | Not recommended |
| 1-2s       | Fair (75-85%)    | Very Good | Edge cases only |
| 2-5s       | Good (85-95%)    | Good | **Optimal** |
| 5-10s      | Excellent (95%+) | Fair | Fallback for long pauses |
| > 10s      | Excellent (95%+) | Poor | Force chunk at 10s |

### Processing Optimization

1. **Concurrent Transcription**: Process up to 3 chunks in parallel
2. **Chunk Prefetching**: Begin processing next chunk before current completes
3. **Result Caching**: Cache transcriptions for retry scenarios
4. **Context Window**: Include last 100 words from previous chunk for continuity

## User Experience

### Visual Feedback

1. **Live Transcription Display**:
   ```
   ┌─────────────────────────────────────┐
   │ 🎤 Edit Mode (Recording: 0:15)      │
   ├─────────────────────────────────────┤
   │ "Make this paragraph more formal    │
   │  and add a conclusion about..."     │
   │                                     │
   │ [░░░░░░████████░░░░] Processing...  │
   └─────────────────────────────────────┘
   ```

2. **Chunk Processing Indicators**:
   - Show number of chunks processed
   - Indicate when chunk is being transcribed
   - Display partial transcription as available

### Audio Feedback

1. **Subtle chunk confirmation**: Quiet beep when chunk is sent
2. **Processing status**: Different tones for success/retry
3. **Completion sound**: When all chunks are processed

## Testing Strategy

### Unit Tests

1. **Chunk Size Validation**:
   - Test minimum chunk enforcement
   - Test maximum chunk splitting
   - Test silence-based chunking

2. **Transcription Assembly**:
   - Test in-order assembly
   - Test with missing chunks
   - Test with overlapping audio

### Integration Tests

1. **End-to-End Flow**:
   - Record 30s edit instruction with pauses
   - Verify progressive transcription
   - Confirm final edit accuracy

2. **Network Conditions**:
   - Test with slow connections
   - Test with intermittent failures
   - Test offline queuing

### Performance Tests

1. **Latency Measurements**:
   - Time from speech end to transcription start
   - Time from chunk ready to UI update
   - Total time vs. current implementation

2. **Resource Usage**:
   - Memory usage with multiple chunks
   - CPU usage during parallel processing
   - Network bandwidth optimization

## Migration Plan

### Phase 1: Infrastructure (Week 1)
- Implement ProgressiveEditChunker
- Add chunk-aware VAD mode
- Create transcription manager

### Phase 2: Integration (Week 2)
- Update AudioEngine for progressive mode
- Modify WhisperService for chunks
- Update EditManager state machine

### Phase 3: UI/UX (Week 3)
- Add live transcription display
- Implement progress indicators
- Add audio feedback

### Phase 4: Optimization (Week 4)
- Tune chunk size thresholds
- Optimize parallel processing
- Add retry mechanisms

## Success Metrics

1. **Perceived Latency**: 50% reduction in time from stop to result
2. **Transcription Accuracy**: Maintain 95%+ accuracy
3. **User Satisfaction**: Positive feedback on responsiveness
4. **Resource Efficiency**: No increase in API costs

## Future Enhancements

1. **Streaming GPT Processing**: Start edit generation before full transcription
2. **Incremental Edits**: Apply edits progressively as chunks complete
3. **Smart Chunking**: Use NLP to detect sentence boundaries
4. **Offline Mode**: Local transcription for simple edits