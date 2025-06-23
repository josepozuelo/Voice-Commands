# Voice Command Chunking Design and Pseudocode

## Overview

The voice command system uses a multi-layered approach to chunk audio and process commands. The issue where "Error command not detected" appears before successful execution likely stems from multiple audio chunks being processed, with the first chunk containing incomplete speech.

## Current Architecture

### Layer 1: Audio Capture (AudioEngine.swift)
- Captures raw audio from microphone at native sample rate
- Converts to target sample rate (16kHz for Whisper)
- In continuous mode, feeds audio to VADChunker for speech detection

### Layer 2: Voice Activity Detection (VADChunker.swift)
- Uses frame-based voice detection with counters:
  - `voiceFrameCount`: Consecutive voiced frames (resets on silence)
  - `silenceFrameCount`: Consecutive silent frames (resets on voice)
  - `totalSpeechFrames`: Cumulative voiced frames in chunk
- Speech start threshold: 5 frames (100ms) to ignore coughs/clicks
- Speech end threshold: 25 frames (500ms) of silence
- Emits chunks when silence threshold is reached after speech

### Layer 3: Command Processing (CommandManager.swift)
- Receives audio chunks via `audioChunkPublisher`
- Sends to WhisperService for transcription
- On transcription result:
  - Empty text → Shows "No speech detected" error
  - Non-empty text → Sends to CommandClassifier

### Layer 4: Command Classification (CommandClassifier.swift)
- Uses GPT-4o-mini to classify transcribed text
- Returns CommandJSON with intent (select, move, shortcut, etc.)
- If no match found, returns intent="none"

## Identified Issues

### Problem: "Error command not detected" followed by successful execution

**Root Cause Analysis:**
1. VADChunker may emit multiple chunks for a single utterance:
   - First chunk: Partial speech that gets transcribed but doesn't match any command
   - Second chunk: Complete command that executes successfully

2. The issue occurs because:
   - VADChunker accumulates all audio in `currentChunk` buffer
   - When speech ends, it emits the ENTIRE buffer (including pre-speech silence)
   - If user pauses mid-command, it could trigger premature chunk emission

## Pseudocode

### Current Flow
```
// AudioEngine.swift - processAudioBuffer()
if isContinuousMode:
    convert buffer to float array
    vadChunker.processAudioBuffer(floatArray)

// VADChunker.swift - processAudioBuffer()
for each frame in buffer:
    isVoiced = detectVoice(frame)
    
    if isVoiced:
        voiceFrameCount++
        silenceFrameCount = 0
        totalSpeechFrames++
        
        if voiceFrameCount == minSpeechFrames:
            inSpeech = true
    else:
        silenceFrameCount++
        voiceFrameCount = 0
    
    if inSpeech && silenceFrameCount >= trailingSilenceFrames:
        emitChunk(currentChunk)
        resetState()

// CommandManager.swift - processAudioChunk()
if hudState == continuousListening:
    hudState = processing
    whisperService.transcribe(chunk)

// On transcription complete
if text.isEmpty:
    showError("No speech detected")
else:
    classifyAndExecute(text)

// CommandClassifier returns intent="none"
showError("No matching command found")
```

### Issue Manifestation
```
User says: "select word" (with brief pause after "select")

Time 0ms: User starts speaking "select"
Time 300ms: Speech detected, inSpeech = true
Time 500ms: User pauses briefly after "select"
Time 1000ms: Silence threshold reached
    → Chunk 1 emitted: "select"
    → Transcribed successfully
    → Classification fails (incomplete command)
    → Error shown: "No matching command found"

Time 1100ms: User continues with "word"
Time 1600ms: Silence threshold reached
    → Chunk 2 emitted: "word" 
    → Transcribed successfully
    → Classification succeeds
    → Command executed
```

## Solution Approaches

### 1. Increase Minimum Speech Duration
- Increase `minSpeechFrames` from 5 (100ms) to 15 (300ms)
- Helps filter out very short utterances

### 2. Add Pre-Classification Validation
- Check if transcribed text appears to be a complete command
- Buffer incomplete commands for concatenation with next chunk

### 3. Implement Command Confidence Scoring
- If classification confidence is low, wait for next chunk
- Concatenate chunks if they appear related

### 4. Adjust Silence Detection Thresholds
- Increase `trailingSilenceFrames` from 25 (500ms) to 35 (700ms)
- Reduces likelihood of mid-command splits

### 5. Add Chunk Overlap
- Keep last 200ms of previous chunk
- Helps capture words that might be cut off at boundaries

## Recommended Fix

The most robust solution would be to implement a command completion detector that:
1. Analyzes transcribed text for command completeness
2. Buffers incomplete commands
3. Concatenates with subsequent chunks if needed
4. Only shows errors after a longer timeout period

This would prevent premature error messages while maintaining responsive command execution.