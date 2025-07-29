# Always-Capture Audio Implementation Checklist

## Phase 1: Modify VADSilenceDetector ✅
- [x] Remove conditional audio accumulation (lines 97-99)
- [x] Always append audio to currentAudioChunk regardless of state
- [x] Add debug logging for chunk sizes
- [x] Modify voiceStarted to not clear accumulated audio
- [x] Modify voiceEnded to emit full accumulated chunk with logging

## Phase 2: Update VADChunker ✅
- [x] Ensure VADChunker passes through all audio data
- [x] Add logging to track audio flow

## Phase 3: Update AudioEngine ✅
- [x] Verify continuous audio capture in processAudioBuffer
- [x] Add debug logging for audio pipeline
- [x] Add periodic logging for continuous capture progress
- [x] Add debug counters to track audio flow

## Phase 4: Testing
- [ ] Test with soft-spoken commands
- [ ] Test with commands starting with unvoiced consonants (p, t, k, f, s)
- [ ] Test continuous mode with multiple commands
- [ ] Verify no audio is lost at command beginnings
- [ ] Check chunk sizes and timing

## Implementation Notes
- Keep existing VAD state machine for compatibility
- Focus on changing data flow, not decision logic
- Add comprehensive logging for debugging
- Maintain backward compatibility with existing command flow