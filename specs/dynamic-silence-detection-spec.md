# Dynamic Silence Detection - Design Specification

## Problem Statement

The current fixed threshold approach causes two critical issues:
1. **False Positives**: "No command detected" triggers from background noise changes
2. **False Negatives**: Missed speech in environments where ambient noise is near the threshold

## Solution: Adaptive Relative Detection

### Core Concept

Instead of fixed thresholds, use relative changes from a rolling baseline:
- Track ambient noise level continuously
- Detect speech as significant increase above baseline
- Detect silence as return to near-baseline levels

### Design Elements

## 1. Adaptive Background Noise Tracking

```swift
struct AdaptiveNoiseTracker {
    // Rolling statistics
    private var shortTermAverage: Float = 0.0  // 1-second window
    private var longTermAverage: Float = 0.0   // 10-second window
    private var noiseFloor: Float = 0.0        // Minimum observed
    private var standardDeviation: Float = 0.0  // Noise variability
    
    // Circular buffer for recent RMS values
    private var rmsHistory: CircularBuffer<Float> = CircularBuffer(capacity: 160) // 10s at 16Hz
    
    // Update with new RMS value
    mutating func update(rms: Float) {
        rmsHistory.append(rms)
        updateStatistics()
    }
    
    // Get dynamic thresholds
    func getSpeechThreshold() -> Float {
        // Speech = baseline + 2 standard deviations OR 2x baseline (whichever is larger)
        return max(
            longTermAverage + (2.0 * standardDeviation),
            longTermAverage * 2.0
        )
    }
    
    func getSilenceThreshold() -> Float {
        // Silence = baseline + 0.5 standard deviations
        return longTermAverage + (0.5 * standardDeviation)
    }
}
```

## 2. Relative Detection Algorithm

```swift
enum DetectionState {
    case calibrating        // Initial noise floor calibration
    case waitingForSpeech  // Monitoring for speech
    case detectingSpeech   // Active speech detected
    case trailingSilence   // Speech ended, waiting for silence duration
}

class DynamicSilenceDetector {
    private var state: DetectionState = .calibrating
    private var noiseTracker = AdaptiveNoiseTracker()
    private var speechStartTime: Date?
    private var silenceStartTime: Date?
    private var lastRMS: Float = 0.0
    private var consecutiveHighSamples = 0
    private var consecutiveLowSamples = 0
    
    // Configurable parameters
    var calibrationDuration: TimeInterval = 0.5
    var minSpeechDuration: TimeInterval = 0.1    // Avoid micro-spikes
    var silenceDuration: TimeInterval = 0.5       // Reduced from 0.8s
    var confirmationSamples: Int = 3              // Samples needed to confirm state change
    
    func process(rms: Float, timestamp: Date) -> DetectionResult {
        noiseTracker.update(rms: rms)
        
        // Get dynamic thresholds
        let speechThreshold = noiseTracker.getSpeechThreshold()
        let silenceThreshold = noiseTracker.getSilenceThreshold()
        
        // Calculate rate of change (helps detect sharp transitions)
        let rmsChange = abs(rms - lastRMS)
        lastRMS = rms
        
        switch state {
        case .calibrating:
            // Initial calibration period
            if timestamp.timeIntervalSince(startTime) >= calibrationDuration {
                state = .waitingForSpeech
            }
            
        case .waitingForSpeech:
            if rms >= speechThreshold {
                consecutiveHighSamples += 1
                if consecutiveHighSamples >= confirmationSamples {
                    state = .detectingSpeech
                    speechStartTime = timestamp
                    consecutiveHighSamples = 0
                }
            } else {
                consecutiveHighSamples = 0
            }
            
        case .detectingSpeech:
            if rms < silenceThreshold {
                consecutiveLowSamples += 1
                if consecutiveLowSamples >= confirmationSamples {
                    // Check if speech was long enough
                    if let start = speechStartTime, 
                       timestamp.timeIntervalSince(start) >= minSpeechDuration {
                        state = .trailingSilence
                        silenceStartTime = timestamp
                    } else {
                        // Too short, probably noise
                        state = .waitingForSpeech
                    }
                    consecutiveLowSamples = 0
                }
            } else {
                consecutiveLowSamples = 0
            }
            
        case .trailingSilence:
            if rms >= speechThreshold {
                // Speech resumed
                state = .detectingSpeech
                silenceStartTime = nil
            } else if let start = silenceStartTime,
                      timestamp.timeIntervalSince(start) >= silenceDuration {
                // Silence confirmed - process chunk
                state = .waitingForSpeech
                return .chunkReady
            }
        }
        
        return .continue
    }
}
```

## 3. Enhanced Noise Statistics

```swift
extension AdaptiveNoiseTracker {
    // Use exponentially weighted moving average for smooth adaptation
    mutating func updateStatistics() {
        guard rmsHistory.count > 0 else { return }
        
        // Short-term average (last 1 second = ~16 samples)
        let shortSamples = Array(rmsHistory.suffix(16))
        shortTermAverage = shortSamples.reduce(0, +) / Float(shortSamples.count)
        
        // Long-term average (all samples, up to 10 seconds)
        let allSamples = Array(rmsHistory)
        longTermAverage = allSamples.reduce(0, +) / Float(allSamples.count)
        
        // Standard deviation for variability
        let variance = allSamples.map { pow($0 - longTermAverage, 2) }.reduce(0, +) / Float(allSamples.count)
        standardDeviation = sqrt(variance)
        
        // Noise floor (5th percentile)
        let sorted = allSamples.sorted()
        let index = Int(Float(sorted.count) * 0.05)
        noiseFloor = sorted[index]
    }
}
```

## 4. Integration with AudioEngine

```swift
// In AudioEngine.swift
class AudioEngine {
    private let dynamicDetector = DynamicSilenceDetector()
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let rms = calculateRMS(buffer: buffer)
        
        // Use dynamic detection
        let result = dynamicDetector.process(rms: rms, timestamp: Date())
        
        switch result {
        case .chunkReady:
            // Process the accumulated audio chunk
            processSilenceDetected()
        case .continue:
            // Keep accumulating audio
            appendToCurrentChunk(buffer)
        }
    }
}
```

## 5. Adaptive Parameters

### Environment-Specific Adjustments

```swift
struct AdaptiveParameters {
    // Multipliers adjust based on noise characteristics
    var speechMultiplier: Float = 2.0      // How much above baseline for speech
    var silenceMultiplier: Float = 1.3     // How much above baseline for silence
    
    // Adjust based on environment
    mutating func adaptToEnvironment(noiseStats: NoiseStatistics) {
        if noiseStats.standardDeviation < 0.005 {
            // Very quiet environment - more sensitive
            speechMultiplier = 1.5
            silenceMultiplier = 1.2
        } else if noiseStats.standardDeviation > 0.02 {
            // Noisy environment - less sensitive
            speechMultiplier = 2.5
            silenceMultiplier = 1.5
        }
    }
}
```

## 6. Advanced Features

### A. Spectral Analysis Option

```swift
// For even better detection, analyze frequency content
func analyzeSpectrum(buffer: AVAudioPCMBuffer) -> Bool {
    // Human speech is typically 85-255 Hz (fundamental frequency)
    // Check if energy is concentrated in speech frequencies
    let fft = performFFT(buffer)
    let speechBandEnergy = fft.energyInRange(85...255)
    let totalEnergy = fft.totalEnergy
    
    return (speechBandEnergy / totalEnergy) > 0.4
}
```

### B. Machine Learning Option

```swift
// Use Core ML for advanced voice activity detection
class MLVoiceDetector {
    private let model: VoiceActivityDetection // Core ML model
    
    func detectVoiceActivity(features: AudioFeatures) -> Float {
        // Returns probability 0.0-1.0
        return model.prediction(features).voiceProbability
    }
}
```

## Benefits

1. **Adaptive to Environment**: Works in quiet rooms and noisy cafes
2. **No False Triggers**: Background noise changes don't trigger commands
3. **Consistent Detection**: Relative thresholds ensure reliable speech detection
4. **Smooth Operation**: Statistical approach prevents abrupt changes
5. **Configurable**: Easy to tune for different use cases

## Implementation Strategy

### Phase 1: Basic Dynamic Detection
- Implement rolling average baseline
- Simple relative thresholds (2x for speech, 1.3x for silence)
- Test in various environments

### Phase 2: Statistical Enhancement
- Add standard deviation tracking
- Implement confirmation sample requirements
- Add rate-of-change detection

### Phase 3: Advanced Features
- Spectral analysis for better accuracy
- ML-based detection option
- Per-user calibration profiles

## Configuration

```swift
// In Config.swift
struct DynamicDetectionConfig {
    // Baseline tracking
    static let shortTermWindowSeconds: TimeInterval = 1.0
    static let longTermWindowSeconds: TimeInterval = 10.0
    
    // Detection multipliers
    static let defaultSpeechMultiplier: Float = 2.0
    static let defaultSilenceMultiplier: Float = 1.3
    
    // Timing
    static let calibrationDuration: TimeInterval = 0.5
    static let minSpeechDuration: TimeInterval = 0.1
    static let silenceDuration: TimeInterval = 0.5
    
    // Confirmation
    static let confirmationSamples: Int = 3
    
    // Adaptive bounds
    static let minSpeechThreshold: Float = 0.01  // Never go below this
    static let maxSpeechThreshold: Float = 0.5   // Never go above this
}
```

## Testing Strategy

1. **Quiet Room Test**: Baseline ~0.001, speech at 0.01
2. **Office Environment**: Baseline ~0.01, speech at 0.05
3. **Noisy Cafe**: Baseline ~0.03, speech at 0.1
4. **Dynamic Scenarios**: TV in background, music playing
5. **Edge Cases**: Sudden loud noises, gradual volume changes

This approach ensures robust detection across all environments while preventing both false positives and false negatives.