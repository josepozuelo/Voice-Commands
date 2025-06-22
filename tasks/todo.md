# LLM Voice Commands Implementation Plan

## Overview
Transition from fuzzy-matching command system to LLM-based intent classification with improved VAD-based audio chunking.

## Phase 1: Command Classification Infrastructure

### 1.1 Create CommandClassifier
- [ ] Create `Core/CommandClassifier.swift` 
- [ ] Implement OpenAI chat completions API call with ultra-compact schema prompt
- [ ] Define `CommandJSON` data structures for all 7 intent types
- [ ] Add error handling for API failures and invalid responses
- [ ] Use `gpt-4o-mini` model for low latency

### 1.2 Update Command Models
- [ ] Create new intent-based command structures in `Models/CommandIntent.swift`
- [ ] Support all 7 intents: shortcut, select, move, tab, overlay, dictation, edit
- [ ] Add JSON parsing for each intent type
- [ ] Keep backwards compatibility during transition

## Phase 2: Audio Processing & VAD

### 2.1 Implement Frame-Level VAD
- [ ] Complete `Core/VADSilenceDetector.swift` implementation
- [ ] Add WebRTC VAD library or implement frame-level detection
- [ ] Process audio in 20ms frames (320 samples @ 16kHz)
- [ ] Return voiced/unvoiced classification per frame

### 2.2 Implement VADChunker with 3-Level State Management
- [ ] Create `Core/VADChunker.swift` for chunk boundary detection
- [ ] Level 1: Frame detection (voiced/unvoiced per 20ms)
- [ ] Level 2: Counter tracking (voiceFrameCount, silenceFrameCount, totalSpeechFrames)
- [ ] Level 3: Chunk state (inSpeech boolean gate, currentChunk buffer)

### 2.3 Implement State Transitions
- [ ] Not Speaking → Speaking: voiceFrameCount >= 5 (100ms)
- [ ] Speaking → Chunk Emission: silenceFrameCount >= 25 (500ms)
- [ ] Chunk validation: only emit if totalSpeechFrames >= 5
- [ ] Add maxChunkLength safety cutoff (10s)
- [ ] Reset all state after chunk emission

### 2.4 Implement Chunk Processing
- [ ] Add leading/trailing silence trimming before Whisper
- [ ] Handle edge cases (brief noise, mid-sentence pauses)
- [ ] Ensure no gaps between chunks (continuous recording)

### 2.5 Update AudioEngine
- [ ] Ensure continuous recording with no gaps between chunks
- [ ] Remove mode-specific logic (always continuous)
- [ ] Integrate VADChunker for chunk detection
- [ ] Add debug logging for VAD states every 2 seconds

## Phase 3: Integration & Routing

### 3.1 Create CommandRouter
- [ ] Create `Core/CommandRouter.swift` to dispatch CommandJSON
- [ ] Route shortcut/select/move/tab to AccessibilityBridge
- [ ] Add placeholder handlers for dictation/edit/overlay
- [ ] Handle "none" intent with appropriate feedback

### 3.2 Update CommandManager
- [ ] Remove CommandMatcher dependency
- [ ] Integrate CommandClassifier for intent detection
- [ ] Update continuous mode to use new VAD-based chunking
- [ ] Remove disambiguation logic (no longer needed with LLM)
- [ ] Update HUD to show processing states

### 3.3 Update AccessibilityBridge
- [ ] Add support for new command intent structures
- [ ] Map intent parameters to existing functionality
- [ ] Ensure compatibility with select/move/shortcut intents

## Phase 4: Testing & Refinement

### 4.1 Test Core Functionality
- [ ] Test VAD accuracy with various speech patterns
- [ ] Verify chunk boundaries don't cut off words
- [ ] Test LLM classification accuracy
- [ ] Measure end-to-end latency

### 4.2 Optimize Performance
- [ ] Fine-tune VAD parameters for best results
- [ ] Optimize chunk size for Whisper accuracy
- [ ] Monitor and log classification confidence
- [ ] Add metrics for debugging

## Phase 5: MVP Features (SELECT intent only)

### 5.1 Implement SELECT Intent
- [ ] Map natural language to selection units (word, sentence, paragraph, etc.)
- [ ] Support direction modifiers (this, next, previous)
- [ ] Handle count parameters
- [ ] Test with common selection phrases

### 5.2 Polish User Experience
- [ ] Update HUD to show transcription and intent
- [ ] Add visual feedback for VAD states
- [ ] Improve error messages
- [ ] Update continuous mode indicator

## Implementation Order

1. Start with CommandClassifier (can test independently)
2. Implement VAD and chunking (critical for accuracy)
3. Integrate components through CommandRouter
4. Update CommandManager for new flow
5. Test and refine SELECT intent
6. Polish user experience

## Notes

- Keep existing functionality working during transition
- Test each component in isolation before integration
- Focus on SELECT intent for MVP (defer SHORTCUT implementation)
- Ensure proper error handling at each stage
- Add comprehensive logging for debugging