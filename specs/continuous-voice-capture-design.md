# Continuous Voice Command Capture - Design & Implementation

## Overview

This document describes the current implementation of the continuous voice command capture system in VoiceControl. The system features dynamic silence detection that adapts to ambient noise levels in real-time for accurate and responsive voice command processing.

## System Architecture

### High-Level Flow

```
User Input → Audio Capture → Chunk Detection → Transcription → Command Matching → Execution
     ↑                                                                                    ↓
     └──────────────────────── Continuous Loop ←─────────────────────────────────────┘
```

### Core Components

1. **AudioEngine** - Handles microphone capture and dynamic silence detection
2. **WhisperService** - Manages OpenAI Whisper API transcription
3. **CommandManager** - Orchestrates the continuous workflow
4. **CommandMatcher** - Performs fuzzy matching on transcribed text
5. **CommandHUD** - Provides visual feedback and disambiguation

## Audio Processing Pipeline

### Audio Capture

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
4. Dynamic silence detection triggers chunk boundaries

### Dynamic Silence Detection

The system uses three key components for adaptive silence detection:

#### 1. CircularBuffer
- Generic data structure for efficient RMS history tracking
- Maintains 160 samples (10 seconds at 16Hz)
- O(1) append operations with automatic wraparound
- Provides suffix and iteration capabilities

#### 2. AdaptiveNoiseTracker
Tracks real-time noise statistics:
- **Long-term average**: Mean of all samples in buffer
- **Short-term average**: Mean of last 16 samples (~1 second)
- **Standard deviation**: Measure of noise variability
- **Noise floor**: 5th percentile of samples

#### 3. DynamicSilenceDetector
State machine with four states:

```
┌─────────────┐
│ Calibrating │ (500ms) → Collect baseline noise statistics
└──────┬──────┘
       ↓
┌──────────────────┐
│ WaitingForSpeech │ → Monitor for RMS > speechThreshold
└────────┬─────────┘    (requires 3 consecutive samples)
         ↓
┌──────────────────┐
│ DetectingSpeech  │ → Continue recording while RMS > silenceThreshold
└────────┬─────────┘
         ↓
┌──────────────────┐
│ TrailingSilence  │ → Wait for 500ms of silence
└──────────────────┘    Then emit chunk if duration > 100ms
```

### Adaptive Threshold Calculation

Thresholds are calculated dynamically based on noise statistics:

```
Speech Threshold = max(baseline + 2σ, baseline × 2.0)
Silence Threshold = baseline + 0.5σ

Where:
  - baseline = long-term RMS average
  - σ = standard deviation of RMS values
  - Bounds: [0.01, 0.5] to prevent extreme values
```

### Configuration Parameters

```swift
// From Config.swift
calibrationDuration: 0.5 seconds      // Initial noise floor calibration
minSpeechDuration: 0.1 seconds        // Minimum valid speech length
silenceDuration: 0.8 seconds          // Silence required to end chunk (increased for better separation)
confirmationSamples: 3                // Samples needed to confirm speech
speechMultiplier: 2.0                 // Multiplier for speech threshold
silenceMultiplier: 1.3                // Multiplier for silence threshold
maxAudioChunkDuration: 10 seconds     // Maximum chunk length (safety)
minimumChunkGap: 0.2 seconds          // Minimum gap between chunks to prevent overlap
```

## Command Processing Pipeline

### 1. Chunk Creation
When the DynamicSilenceDetector returns `chunkReady`:
- Minimum chunk gap (200ms) is enforced to prevent overlap
- Current audio buffer is sent via Combine publisher
- Buffer is cleared for next chunk
- Detector resets to `waitingForSpeech` state
- Timestamp is recorded for gap enforcement

### 2. Transcription
- Audio chunk sent to WhisperService
- Uses OpenAI Whisper API (model: whisper-1)
- Returns transcribed text asynchronously

### 3. Command Matching
- Fuzzy matching against commands.json
- Confidence threshold: 0.85
- Returns matched command(s) or disambiguation options

### 4. Execution
- High confidence matches execute automatically
- Multiple matches show disambiguation HUD
- Voice-enabled disambiguation ("one", "two", "three")

## Performance Characteristics

### Latency Breakdown
- **Audio Capture**: ~50ms buffering delay
- **Silence Detection**: 800ms-1200ms (adaptive, VAD-based)
- **Chunk Gap**: 200ms minimum between chunks
- **Whisper API**: 500ms-2000ms (network dependent)
- **Command Matching**: <10ms
- **Total**: ~1.55-3.45 seconds end-to-end

### Memory Usage
- Audio buffer: ~32KB/second (16kHz × 2 bytes)
- RMS history: 640 bytes (160 floats)
- Maximum chunk size: ~320KB (10 seconds)

### Accuracy
- Adapts to ambient noise in 500ms
- Prevents false triggers in quiet environments
- Maintains detection in noisy environments
- Minimum speech duration prevents accidental triggers

## Operating Modes

### Single Command Mode
- Activated by hotkey press
- Records single command
- Stops after execution

### Continuous Mode (Default)
- Toggle with hotkey (⌃⇧V)
- Continuous recording with automatic chunking
- Visual indicator in HUD
- Press hotkey again to stop

## Debug Features

### Threshold Logging
Every 2 seconds, the system logs:
```
Dynamic thresholds - Speech: 0.034, Silence: 0.018, Current RMS: 0.012
```

This provides visibility into:
- Current adaptive thresholds
- Ambient noise level
- System responsiveness

## Implementation Details

### Key Classes and Their Responsibilities

**AudioEngine.swift**
- Manages AVAudioEngine lifecycle
- Processes audio buffers
- Integrates DynamicSilenceDetector
- Publishes audio chunks

**CircularBuffer.swift**
- Generic circular buffer implementation
- Efficient append and iteration
- Memory-bounded history tracking

**DynamicSilenceDetector** (in AudioEngine.swift)
- State machine for speech detection
- Adaptive threshold calculation
- Chunk boundary detection

**AdaptiveNoiseTracker** (in AudioEngine.swift)
- Statistical analysis of RMS values
- Noise floor tracking
- Real-time updates

### Data Flow

1. **Audio Input**: Microphone → AVAudioEngine → AudioEngine.processAudioBuffer()
2. **Analysis**: RMS calculation → DynamicSilenceDetector.process()
3. **Statistics**: AdaptiveNoiseTracker.update() → Threshold recalculation
4. **Detection**: State transitions → Chunk emission
5. **Processing**: CommandManager → WhisperService → CommandMatcher
6. **Execution**: AccessibilityBridge → System actions

## Audio Chunk Separation Improvements

To prevent short commands from being appended to subsequent commands, the system implements several safeguards:

### Buffer Management
1. **Selective Audio Accumulation** (VAD mode only): Audio is only accumulated during speech and trailing silence states
2. **Clean Buffer Start**: All buffers are cleared when starting continuous recording
3. **Complete Buffer Clear**: Buffers are cleared after sending chunks and when stopping recording

### Timing Controls
1. **Minimum Chunk Gap**: 200ms enforced gap between chunks prevents overlap
2. **Increased Silence Duration**: 
   - VAD: 1200ms silence timeout (was 1000ms)
   - Dynamic: 800ms silence duration (was 500ms)
3. **State Reset**: Confirmation counters and state variables are properly reset between chunks

### Processing Safeguards
1. **State Checking**: Audio chunks are only processed in appropriate states
2. **Clean State Transitions**: HUD state and recognized text are cleared between commands
3. **Detector Reset**: Both VAD and dynamic detectors are reset when stopping recording

These improvements ensure that each voice command is processed as a distinct, isolated chunk, preventing the concatenation of commands that was causing issues with short utterances.

## Summary

The continuous voice capture system provides a robust, adaptive solution for hands-free command execution. The dynamic silence detection ensures reliable operation across varying acoustic environments while maintaining low latency and high accuracy. The system continuously adapts to ambient conditions, providing a natural and responsive user experience. Recent improvements to buffer management and timing controls ensure clean separation between commands, preventing concatenation issues.