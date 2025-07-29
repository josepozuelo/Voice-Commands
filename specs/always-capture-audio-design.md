# Always-Capture Audio Design

## Problem Statement

Currently, VoiceControl loses the beginning of voice commands (~300ms) because audio accumulation only starts AFTER the Voice Activity Detection (VAD) confirms speech presence. This leads to commands being cut off at the start, especially those beginning with soft-spoken words or unvoiced consonants.

### Root Cause
1. VAD requires ~10 frames (320ms) to confirm speech detection
2. Audio is only accumulated when VAD state is `speechDetected` or `trailingSilence`
3. The pre-trigger buffer was removed in commit b8d1ff1
4. Any audio before VAD confirmation is discarded

## Proposed Solution

Implement an "always-capture" audio pipeline where:
1. **Audio is continuously captured and buffered** from the moment recording starts
2. **VAD runs in parallel** to detect speech boundaries
3. **VAD is used only for:**
   - Determining when to split audio into chunks
   - Tagging whether a chunk contains speech
   - Deciding if a chunk should be sent to Whisper API

## Design Details

### Audio Flow Architecture

```
┌─────────────────┐
│  AudioEngine    │
│ (Continuous     │
│  Capture)       │
└────────┬────────┘
         │ Raw Audio Stream
         ▼
┌─────────────────┐
│ Audio Buffer    │
│ (Accumulates    │
│  all audio)     │
└────────┬────────┘
         │
         ├──────────────┐
         ▼              ▼
┌─────────────────┐  ┌─────────────────┐
│ VAD Detector    │  │ Audio Data      │
│ (Silero v5)     │  │ (Full capture)  │
└────────┬────────┘  └─────────────────┘
         │
         ▼
┌─────────────────┐
│ Chunk Decision  │
│ - Split points  │
│ - Speech tags   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Whisper API     │
│ (If chunk has   │
│  speech)        │
└─────────────────┘
```

### Key Changes

#### 1. VADSilenceDetector Modifications
- **Always accumulate audio** in `currentAudioChunk` regardless of VAD state
- Use VAD only for decision-making, not for controlling accumulation
- When VAD detects speech end, emit the **entire accumulated chunk** (including pre-speech audio)

#### 2. VAD State Machine Changes
- Keep existing states but change their meaning:
  - `idle`: No speech detected yet, but still accumulating audio
  - `speechDetected`: Speech confirmed, continue accumulating
  - `trailingSilence`: Speech ended, waiting for silence confirmation
- Add timestamp markers for chunk boundaries

#### 3. Chunk Emission Logic
- When VAD confirms speech end:
  1. Emit entire accumulated audio chunk (from last chunk end to current)
  2. Tag chunk with speech presence metadata
  3. Reset accumulator for next chunk
  4. Only send to Whisper if chunk contains speech

### Implementation Plan

#### Phase 1: Modify VADSilenceDetector
1. Remove conditional accumulation (lines 97-99)
2. Always append audio to `currentAudioChunk` in `processAudioData`
3. Add chunk start timestamp tracking
4. Modify `voiceEnded` callback to emit full chunk

#### Phase 2: Update Chunk Processing
1. Add speech presence flag to chunk metadata
2. Modify VADChunker to pass through all chunks with metadata
3. Update AudioEngine to handle chunk metadata

#### Phase 3: Integrate with CommandManager
1. Filter chunks based on speech presence before sending to Whisper
2. Add debug logging for chunk sizes and speech detection
3. Handle edge cases (very long silence, maximum chunk size)

#### Phase 4: Testing & Optimization
1. Test with various command types (soft/loud start, different consonants)
2. Verify no audio loss at command beginnings
3. Monitor chunk sizes and adjust parameters if needed
4. Test continuous mode with multiple commands

### Benefits

1. **No audio loss**: Every audio sample is captured from recording start
2. **Accurate command capture**: Full commands including soft beginnings
3. **Simpler logic**: VAD only makes decisions, doesn't control data flow
4. **Better debugging**: Can analyze full audio chunks including silence
5. **Future flexibility**: Can adjust chunk boundaries without losing data

### Potential Considerations

1. **Memory usage**: Slightly higher due to capturing all audio
   - Mitigation: Implement maximum chunk size limits
2. **Whisper API calls**: May send slightly larger audio files
   - Mitigation: Only marginal increase (~300ms per chunk)
3. **Chunk boundaries**: Need to handle very long continuous speech
   - Mitigation: Force chunk split after maximum duration

## Migration Path

1. Create feature branch from current state
2. Implement changes incrementally with testing at each phase
3. Add comprehensive logging for before/after comparison
4. Test with real-world command scenarios
5. Monitor performance and adjust parameters

## Success Criteria

1. No commands are cut off at the beginning
2. Command recognition accuracy improves
3. Continuous mode works reliably with proper chunk boundaries
4. No significant performance degradation
5. Debug logs show full audio capture from recording start