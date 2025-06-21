# Continuous Voice Command Capture - Design & Implementation Spec

## Overview

This document describes the current implementation of the continuous voice command capture system in VoiceControl, focusing on the workflow for creating audio chunks and executing commands continuously. It also identifies opportunities for making the flow more snappy, fluid, and error-resistant.

## Current Architecture

### System Flow

```
User Input → Audio Capture → Chunk Detection → Transcription → Command Matching → Execution
     ↑                                                                                    ↓
     └──────────────────────── Continuous Loop ←─────────────────────────────────────┘
```

### Core Components

1. **AudioEngine** - Handles microphone capture and silence detection
2. **WhisperService** - Manages OpenAI Whisper API transcription
3. **CommandManager** - Orchestrates the continuous workflow
4. **CommandMatcher** - Performs fuzzy matching on transcribed text
5. **CommandHUD** - Provides visual feedback and disambiguation

## Audio Chunk Creation Workflow

### 1. Audio Capture Pipeline

```swift
// AudioEngine.swift - Key parameters
bufferSize: 1024 frames
sampleRate: 16kHz (downsampled from device native)
format: PCM Float32
```

**Process:**
1. AVAudioEngine captures raw audio in real-time
2. Audio is buffered into `currentChunkBuffer`
3. Each buffer is analyzed for RMS (Root Mean Square) level
4. Speech/silence detection triggers chunk boundaries

### 2. Silence Detection Algorithm

```swift
speechDetectionThreshold: 0.02 RMS
silenceRMSThreshold: 0.01 RMS
silenceDuration: 0.8 seconds
maxChunkDuration: 10 seconds (safety limit)
```

**Logic Flow:**
```
Audio Buffer → Calculate RMS → 
  If RMS >= 0.02: Mark as speech, reset silence timer
  If RMS < 0.01 AND speech was detected:
    Start/continue silence timer
    If silence >= 0.8s: Create chunk and send for processing
```

### 3. Chunk Processing Pipeline

1. **Chunk Creation**: When silence is detected, current buffer becomes a chunk
2. **Async Publishing**: Chunk sent via Combine publisher to CommandManager
3. **Transcription**: WhisperService sends audio to OpenAI API
4. **Command Matching**: Fuzzy match against commands.json (0.85 confidence threshold)
5. **Execution/Disambiguation**: Auto-execute high confidence, show HUD for ambiguous

## Current Performance Characteristics

### Latency Breakdown

- **Audio Capture**: ~50ms buffering delay
- **Silence Detection**: 800ms minimum wait
- **Whisper API**: 500ms-2000ms (network + processing)
- **Command Matching**: <10ms
- **Total**: ~1.3-2.8 seconds from speech end to execution

### Memory Usage

- Audio buffer grows at ~32KB/second (16kHz × 2 bytes)
- Maximum chunk size: ~320KB (10 seconds)
- No explicit memory limits or cleanup

## Identified Issues & Bottlenecks

### 1. Fixed Silence Detection
- **Issue**: Hard-coded thresholds don't adapt to environment
- **Impact**: False triggers in noisy environments, missed commands in quiet ones

### 2. Sequential Processing
- **Issue**: Must wait for full transcription before next chunk
- **Impact**: Can miss fast consecutive commands

### 3. Network Dependency
- **Issue**: Every command requires internet round-trip
- **Impact**: Latency and reliability issues

### 4. No Streaming Support
- **Issue**: Can't start processing while user is still speaking
- **Impact**: Added ~800ms delay for every command

## Improvement Opportunities

### 1. Adaptive Voice Activity Detection (VAD)

**Current State:**
- Simple RMS threshold checking
- No environmental calibration

**Proposed Enhancement:**
```swift
class AdaptiveVAD {
    // Calibrate on startup
    func calibrateNoiseFloor() -> Float
    
    // Dynamic threshold adjustment
    func updateThresholds(ambientNoise: Float)
    
    // Frequency-based detection
    func detectSpeechUsingSpectrum(buffer: AVAudioPCMBuffer) -> Bool
}
```

**Benefits:**
- More accurate speech detection
- Works in varied environments
- Fewer false positives

### 2. Parallel Processing Pipeline

**Current State:**
- Sequential: Record → Process → Wait → Repeat

**Proposed Enhancement:**
```swift
class ParallelCommandProcessor {
    private let processingQueue = DispatchQueue(label: "processing", attributes: .concurrent)
    private var pendingChunks: [AudioChunk] = []
    
    func processChunkAsync(_ chunk: AudioChunk) {
        processingQueue.async {
            // Process in parallel
            let result = await self.transcribeAndMatch(chunk)
            
            // Execute in order
            DispatchQueue.main.async {
                self.executeInOrder(result)
            }
        }
    }
}
```

**Benefits:**
- Can capture next command while processing previous
- Better handling of rapid commands
- Maintains execution order

### 3. Hybrid Local/Cloud Processing

**Current State:**
- 100% dependent on Whisper API

**Proposed Enhancement:**
- Implement local command detection for common phrases
- Use cloud only for complex/unknown commands
- Cache frequent commands locally

```swift
class HybridRecognizer {
    // Check local cache first
    func recognizeLocally(_ audio: Data) -> Command?
    
    // Fall back to cloud if needed
    func recognizeInCloud(_ audio: Data) async -> Command
}
```

**Benefits:**
- Near-instant response for common commands
- Reduced API costs
- Works offline for cached commands

### 4. Smarter Chunking Strategy

**Current State:**
- Fixed 800ms silence threshold
- No consideration of speech patterns

**Proposed Enhancement:**
```swift
class SmartChunker {
    // Detect natural speech boundaries
    func detectPhraseEnd(buffer: AVAudioPCMBuffer) -> Bool {
        // Analyze:
        // - Energy contour
        // - Pitch patterns
        // - Zero-crossing rate
        // - Spectral features
    }
    
    // Sliding window for better boundaries
    func processSlidingWindow(size: TimeInterval = 0.5)
}
```

**Benefits:**
- More natural command boundaries
- Fewer cut-off commands
- Better handling of pauses within commands

### 5. Pre-emptive Processing

**Current State:**
- Wait for complete silence before processing

**Proposed Enhancement:**
- Start transcription speculatively during brief pauses
- Cancel if speech resumes
- Use if silence confirmed

```swift
class SpeculativeProcessor {
    private var speculativeTask: Task<Transcript, Error>?
    
    func onPossibleSilence() {
        speculativeTask = Task {
            await transcribe(currentBuffer)
        }
    }
    
    func onSpeechResumed() {
        speculativeTask?.cancel()
    }
    
    func onSilenceConfirmed() async {
        let result = await speculativeTask?.value
        processCommand(result)
    }
}
```

**Benefits:**
- Reduced perceived latency
- More responsive feel
- Better for natural speech patterns

## Implementation Priority

### Phase 1: Quick Wins (1-2 days)
1. Reduce silence threshold to 0.5s (test extensively)
2. Implement basic noise floor calibration
3. Add performance metrics/logging

### Phase 2: Core Improvements (3-5 days)
1. Adaptive VAD implementation
2. Parallel processing pipeline
3. Smarter chunk boundaries

### Phase 3: Advanced Features (1-2 weeks)
1. Local command caching
2. Speculative processing
3. Full hybrid recognition system

## Success Metrics

- **Latency**: Reduce end-to-end from 1.3s to <800ms
- **Accuracy**: Maintain >95% command recognition
- **Reliability**: Handle 99% of commands without errors
- **Fluidity**: Support 5+ consecutive commands smoothly

## Conclusion

The current implementation provides a solid foundation but has room for significant improvements in responsiveness and reliability. By implementing adaptive voice detection, parallel processing, and smarter chunking strategies, we can create a more fluid and snappy experience that better matches users' natural speech patterns.