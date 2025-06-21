# Dynamic Silence Detection Implementation

## Overview
Implement adaptive silence/speech detection using relative noise deltas to fix false triggers and missed commands.

## Phase 1: Core Infrastructure ⏳

- [ ] Create `AdaptiveNoiseTracker` struct in AudioEngine.swift
  - [ ] Implement circular buffer for RMS history (10 second window)
  - [ ] Add short-term average calculation (1 second)
  - [ ] Add long-term average calculation (10 seconds)
  - [ ] Add standard deviation calculation

- [ ] Create `DynamicSilenceDetector` class
  - [ ] Define DetectionState enum (calibrating, waitingForSpeech, detectingSpeech, trailingSilence)
  - [ ] Implement state machine logic
  - [ ] Add confirmation sample counting

## Phase 2: Adaptive Threshold Calculation ⏳

- [ ] Implement dynamic threshold methods
  - [ ] Speech threshold: max(baseline + 2σ, baseline × 2.0)
  - [ ] Silence threshold: baseline + 0.5σ
  - [ ] Add min/max bounds for safety

- [ ] Add exponentially weighted moving average (EWMA)
  - [ ] Implement smooth adaptation algorithm
  - [ ] Add noise floor tracking (5th percentile)

## Phase 3: Integration with AudioEngine ⏳

- [ ] Replace fixed threshold logic with dynamic detector
  - [ ] Update `processAudioBuffer()` to use dynamic detection
  - [ ] Maintain backward compatibility with config flag
  - [ ] Add logging for threshold values

- [ ] Update chunk detection logic
  - [ ] Implement minimum speech duration check (100ms)
  - [ ] Reduce silence duration to 500ms (from 800ms)
  - [ ] Add consecutive sample confirmation

## Phase 4: Configuration & Testing ⏳

- [ ] Add configuration parameters to Config.swift
  - [ ] Dynamic detection enable/disable flag
  - [ ] Multiplier parameters
  - [ ] Timing parameters
  - [ ] Confirmation sample count

- [ ] Create test scenarios
  - [ ] Quiet room baseline test
  - [ ] Background noise adaptation test
  - [ ] Sudden noise spike handling
  - [ ] Continuous speech with pauses

## Phase 5: UI Integration (Optional) ⏳

- [ ] Add visual feedback for noise levels
  - [ ] Show current baseline in HUD
  - [ ] Display speech/silence thresholds
  - [ ] Real-time RMS meter

- [ ] Add calibration UI
  - [ ] Manual baseline reset option
  - [ ] Environment preset selection
  - [ ] Threshold adjustment controls

## Implementation Notes

### Key Code Addition to AudioEngine.swift:

```swift
// Add to AudioEngine class
private var adaptiveDetection = AdaptiveDetection()

private struct AdaptiveDetection {
    var isEnabled = true  // Feature flag
    var noiseTracker = AdaptiveNoiseTracker()
    var detector = DynamicSilenceDetector()
    
    // Statistics
    var currentBaseline: Float = 0.0
    var speechThreshold: Float = 0.0
    var silenceThreshold: Float = 0.0
}

// Update processAudioBuffer
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    let rms = calculateRMS(buffer: buffer)
    
    if adaptiveDetection.isEnabled {
        // New dynamic detection
        let result = adaptiveDetection.detector.process(rms: rms, timestamp: Date())
        
        // Log thresholds for debugging
        if frameCount % 160 == 0 {  // Log every 10 seconds
            logger.debug("Baseline: \(adaptiveDetection.currentBaseline), Speech: \(adaptiveDetection.speechThreshold)")
        }
        
        switch result {
        case .chunkReady:
            processSilenceDetected()
        case .continue:
            appendToCurrentChunk(buffer)
        }
    } else {
        // Fallback to original fixed thresholds
        // ... existing code ...
    }
}
```

### Testing Checklist:

1. **Quiet Environment**
   - [ ] Whisper detection works
   - [ ] No false triggers from ambient noise
   - [ ] Baseline stabilizes quickly

2. **Noisy Environment**
   - [ ] Normal speech detected over background noise
   - [ ] TV/music doesn't trigger false commands
   - [ ] Adapts to gradual noise changes

3. **Edge Cases**
   - [ ] Sudden loud noises don't break detection
   - [ ] Long pauses in speech handled correctly
   - [ ] Very short utterances detected

4. **Performance**
   - [ ] No increased CPU usage
   - [ ] Memory usage stays constant
   - [ ] No audio processing delays

## Success Criteria

- Zero false "no command detected" triggers in normal use
- 95%+ speech detection accuracy across all environments  
- Reduced silence detection time (500ms vs 800ms)
- Smooth adaptation to environment changes
- No performance regression