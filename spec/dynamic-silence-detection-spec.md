# Dynamic Silence/Speech Detection Specification

## Overview

This specification details an adaptive audio detection system that dynamically adjusts to varying background noise levels, preventing false triggers and ensuring reliable speech detection in different acoustic environments.

## Problem Statement

Current implementation uses fixed thresholds:
- Silence threshold: 0.01 RMS
- Speech threshold: 0.02 RMS

These fail in:
- Noisy environments (background noise > 0.01)
- Quiet environments (speech < 0.02)
- Variable noise conditions (AC turning on/off, traffic, etc.)

## Solution Design

### Core Concepts

1. **Adaptive Background Noise Tracking**
   - Rolling average of audio levels during "silence" periods
   - Exponentially weighted moving average (EWMA) for smooth adaptation
   - Separate tracking for short-term (1s) and long-term (10s) averages

2. **Relative Detection Thresholds**
   - Speech detection: background_noise × speech_multiplier (default: 2.0)
   - Silence detection: background_noise × silence_multiplier (default: 1.3)
   - Dynamic range limits to prevent extreme thresholds

3. **State Machine**
   - CALIBRATING: Initial noise level assessment
   - WAITING_FOR_SPEECH: Listening for speech onset
   - DETECTING_SPEECH: Speech detected, accumulating audio
   - TRAILING_SILENCE: Speech ended, waiting for silence confirmation

4. **Noise Floor Calibration**
   - Initial 0.5s calibration period on startup
   - Continuous adaptation during silence periods
   - Reset protection to prevent drift

## Implementation Details

### AudioEngine Enhancement

```swift
// New properties for adaptive detection
private struct AdaptiveDetection {
    var shortTermAverage: Float = 0.0  // 1s window
    var longTermAverage: Float = 0.0   // 10s window
    var calibrationSamples: [Float] = []
    var isCalibrated = false
    
    // Adaptive thresholds
    var currentSpeechThreshold: Float = 0.02
    var currentSilenceThreshold: Float = 0.01
    
    // State tracking
    var detectionState: DetectionState = .calibrating
    var stateTransitionTime: Date?
    
    // Configuration
    let speechMultiplier: Float = 2.0      // Speech must be 2x background
    let silenceMultiplier: Float = 1.3     // Silence is 1.3x background
    let minSpeechThreshold: Float = 0.01   // Absolute minimum
    let maxSpeechThreshold: Float = 0.1    // Absolute maximum
    let shortTermAlpha: Float = 0.1        // EWMA factor for short-term
    let longTermAlpha: Float = 0.01        // EWMA factor for long-term
}

enum DetectionState {
    case calibrating
    case waitingForSpeech
    case detectingSpeech
    case trailingSilence
}
```

### Adaptive Detection Algorithm

```swift
private func updateAdaptiveThresholds(rms: Float) {
    // Update moving averages based on state
    switch adaptive.detectionState {
    case .calibrating:
        adaptive.calibrationSamples.append(rms)
        if adaptive.calibrationSamples.count >= 25 { // ~0.5s at typical buffer rate
            let avgNoise = adaptive.calibrationSamples.reduce(0, +) / Float(adaptive.calibrationSamples.count)
            adaptive.shortTermAverage = avgNoise
            adaptive.longTermAverage = avgNoise
            adaptive.isCalibrated = true
            adaptive.detectionState = .waitingForSpeech
            updateThresholds()
        }
        
    case .waitingForSpeech, .trailingSilence:
        // Update background noise estimates during silence
        adaptive.shortTermAverage = (adaptive.shortTermAlpha * rms) + 
                                   ((1 - adaptive.shortTermAlpha) * adaptive.shortTermAverage)
        adaptive.longTermAverage = (adaptive.longTermAlpha * rms) + 
                                  ((1 - adaptive.longTermAlpha) * adaptive.longTermAverage)
        updateThresholds()
        
    case .detectingSpeech:
        // Don't update background during speech
        break
    }
}

private func updateThresholds() {
    // Use the higher of short and long term averages for stability
    let backgroundNoise = max(adaptive.shortTermAverage, adaptive.longTermAverage)
    
    // Calculate adaptive thresholds
    let speechThreshold = backgroundNoise * adaptive.speechMultiplier
    let silenceThreshold = backgroundNoise * adaptive.silenceMultiplier
    
    // Apply limits
    adaptive.currentSpeechThreshold = max(adaptive.minSpeechThreshold, 
                                         min(speechThreshold, adaptive.maxSpeechThreshold))
    adaptive.currentSilenceThreshold = max(backgroundNoise * 1.1, // At least 10% above background
                                          min(silenceThreshold, adaptive.currentSpeechThreshold * 0.8))
}
```

### State Transition Logic

```swift
private func processAdaptiveDetection(rms: Float) {
    guard adaptive.isCalibrated else {
        updateAdaptiveThresholds(rms)
        return
    }
    
    let now = Date()
    
    switch adaptive.detectionState {
    case .waitingForSpeech:
        if rms >= adaptive.currentSpeechThreshold {
            // Speech onset detected
            adaptive.detectionState = .detectingSpeech
            adaptive.stateTransitionTime = now
            hasDetectedSpeech = true
            silenceStartTime = nil
            
            // Log for debugging
            print("Speech detected: RMS \(rms) > threshold \(adaptive.currentSpeechThreshold)")
        } else {
            // Continue updating background noise
            updateAdaptiveThresholds(rms)
        }
        
    case .detectingSpeech:
        if rms < adaptive.currentSilenceThreshold {
            // Potential speech end
            adaptive.detectionState = .trailingSilence
            adaptive.stateTransitionTime = now
            silenceStartTime = now
        }
        
    case .trailingSilence:
        if rms >= adaptive.currentSpeechThreshold {
            // Speech resumed, back to detecting
            adaptive.detectionState = .detectingSpeech
            adaptive.stateTransitionTime = now
            silenceStartTime = nil
        } else if let transitionTime = adaptive.stateTransitionTime,
                  now.timeIntervalSince(transitionTime) >= Config.silenceDuration {
            // Confirmed silence duration met
            processSilenceDetected()
            adaptive.detectionState = .waitingForSpeech
            adaptive.stateTransitionTime = now
            
            // Resume background adaptation
            updateAdaptiveThresholds(rms)
        } else {
            // Still in trailing silence, update background
            updateAdaptiveThresholds(rms)
        }
        
    default:
        break
    }
}
```

### Integration with Continuous Mode

```swift
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    // ... existing RMS calculation ...
    
    if isContinuousMode {
        currentChunkBuffer.append(convertedData)
        
        // Use adaptive detection
        processAdaptiveDetection(rms)
        
        // Check for maximum chunk duration
        if adaptive.detectionState == .detectingSpeech,
           let chunkStart = chunkStartTime,
           Date().timeIntervalSince(chunkStart) >= Config.maxAudioChunkDuration {
            processChunkTimeout()
        }
    } else {
        // Normal recording mode remains unchanged
        audioBuffer.append(convertedData)
        audioDataPublisher.send(convertedData)
    }
}
```

### Additional Features

1. **Noise Spike Protection**
   - Ignore sudden loud noises (door slams, coughs)
   - Require sustained levels for state transitions

2. **Confidence Metrics**
   - Track speech-to-noise ratio
   - Provide confidence score with chunks

3. **Debug Mode**
   - Real-time visualization of thresholds
   - Log state transitions and threshold updates

## Benefits

1. **Adaptive to Environment**
   - Works in quiet rooms and noisy cafes
   - Adjusts as conditions change

2. **Reduced False Positives**
   - No "no command detected" from background noise
   - Better silence detection between commands

3. **Improved Speech Detection**
   - Captures soft speech in quiet environments
   - Handles loud speech in noisy environments

4. **User Experience**
   - More reliable continuous mode
   - Less frustration from missed commands

## Configuration

New Config.swift parameters:
```swift
// Adaptive Detection Configuration
static let adaptiveSpeechMultiplier: Float = 2.0     // Speech must be Nx background
static let adaptiveSilenceMultiplier: Float = 1.3    // Silence threshold multiplier
static let adaptiveMinSpeechThreshold: Float = 0.01  // Absolute minimum
static let adaptiveMaxSpeechThreshold: Float = 0.1   // Absolute maximum
static let adaptiveCalibrationDuration: TimeInterval = 0.5
static let adaptiveShortTermWindow: Float = 0.1      // EWMA alpha for 1s window
static let adaptiveLongTermWindow: Float = 0.01      // EWMA alpha for 10s window
```

## Testing Strategy

1. **Quiet Environment**
   - Library/bedroom
   - Verify soft speech detection

2. **Noisy Environment**
   - Coffee shop/street
   - Verify noise rejection

3. **Variable Conditions**
   - AC cycling on/off
   - Music playing/stopping

4. **Edge Cases**
   - Very loud background noise
   - Nearly silent speech
   - Sudden noise spikes

## Migration Path

1. Add adaptive detection alongside existing system
2. Add debug toggle to compare both methods
3. Extensive testing in various environments
4. Full migration once validated