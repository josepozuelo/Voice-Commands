# Fix Main Thread Publishing Issues Specification

## Overview
This specification addresses the SwiftUI threading violations where `@Published` properties are being modified from background threads. All UI-related state updates in SwiftUI must occur on the main thread to ensure thread safety and prevent crashes or UI glitches.

## Problem Statement
The error "Publishing changes from background threads is not allowed" occurs when `@Published` properties in `ObservableObject` classes are modified outside the main thread. This violates SwiftUI's threading model and can cause:
- UI update delays or failures
- Unpredictable behavior
- Potential crashes
- Performance degradation

## Affected Components

### 1. AudioEngine.swift
- **Properties**: `isRecording`, `audioLevel`
- **Locations**: Lines 94, 174, 190
- **Context**: Audio recording state changes

### 2. CommandManager.swift
- **Properties**: `isContinuousMode`, `isListening`, `hudState`, `recognizedText`, `currentCommand`, `error`, `isProcessingChunk`
- **Multiple violations across async functions and completion handlers**
- **Most critical component with ~20+ violations**

### 3. WhisperService.swift
- **Properties**: `isTranscribing`, `error`, `transcriptionText`
- **Locations**: Lines 285-287
- **Context**: Transcription state updates

### 4. CommandClassifier.swift
- **Properties**: `isClassifying`, `error`
- **Locations**: Lines 73-74, 117-118
- **Context**: Classification state updates

### 5. HotkeyManager.swift
- **Already correctly implemented** - Uses `DispatchQueue.main.async` for all updates

## Solution Approach

### General Pattern
Replace direct property assignments with main thread dispatch:

```swift
// Before (incorrect):
self.isRecording = true

// After (correct) - Option 1: Using MainActor
await MainActor.run {
    self.isRecording = true
}

// After (correct) - Option 2: Using DispatchQueue
DispatchQueue.main.async {
    self.isRecording = true
}
```

### Decision Criteria
1. **Use `await MainActor.run`** when:
   - Already in an async context
   - Need to wait for the update to complete
   - Part of a sequential flow

2. **Use `DispatchQueue.main.async`** when:
   - In a synchronous context
   - Fire-and-forget updates
   - Completion handlers or delegates

## Implementation Plan

### Phase 1: AudioEngine.swift
1. Wrap `isRecording = true` (lines 94, 174) with main thread dispatch
2. Wrap `isRecording = false` (line 190) with main thread dispatch
3. Verify `audioLevel` updates remain on main thread (line 233 - already correct)

### Phase 2: WhisperService.swift
1. Wrap property updates in `startTranscription` (lines 285-287)
2. Ensure all error and transcription updates use main thread

### Phase 3: CommandClassifier.swift
1. Fix `isClassifying` and `error` updates in `classifyTranscript` (lines 117-118)
2. Fix similar updates in `classify` method if needed

### Phase 4: CommandManager.swift (Most Complex)
1. **Group related updates** to minimize dispatch calls
2. **Identify async contexts** vs completion handlers
3. **Fix each method systematically**:
   - `startContinuousMode()` - lines 144-149
   - `stopContinuousMode()` - lines 155-157
   - `startListening()` - lines 194-199
   - `stopListening()` - line 209
   - `processAudioChunk()` - lines 234, 237, 243
   - `handleTranscriptionResult()` - lines 253, 261
   - `resetToIdle()` - lines 304-307
   - `showError()` - lines 321-322
   - `handleError()` - lines 337-338, 342
   - Completion handlers - lines 51, 107

### Phase 5: EditManager Updates
1. Review and fix any `@Published` property updates in EditManager
2. Ensure recording state changes are on main thread

## Testing Strategy

1. **Enable Main Thread Checker** in Xcode scheme
2. **Test each component**:
   - Start/stop recording
   - Continuous mode transitions
   - Error scenarios
   - Transcription flow
   - Command classification

3. **Monitor console** for threading warnings
4. **Verify UI responsiveness** after fixes

## Code Style Guidelines

1. **Group related updates** in a single main thread dispatch when possible:
```swift
await MainActor.run {
    self.isListening = true
    self.hudState = .listening
    self.error = nil
}
```

2. **Preserve existing error handling** - wrap only the UI updates
3. **Add comments** for complex threading scenarios
4. **Keep dispatch blocks small** - only UI updates, not business logic

## Risks and Mitigations

### Risks
1. **Deadlocks** if MainActor.run is used incorrectly
2. **Performance impact** from excessive dispatching
3. **Timing issues** if updates are reordered

### Mitigations
1. Use `DispatchQueue.main.async` for fire-and-forget updates
2. Group related updates to minimize dispatch overhead
3. Test thoroughly with Main Thread Checker enabled
4. Review each change for potential side effects

## Success Criteria

1. No "Publishing changes from background threads" warnings in console
2. All UI updates happen smoothly without delays
3. No regressions in functionality
4. Code remains readable and maintainable
5. Performance remains acceptable

## Future Considerations

1. Consider using `@MainActor` class annotation for UI-heavy classes
2. Implement lint rules to catch threading violations
3. Add unit tests that verify main thread execution
4. Document threading requirements in code comments