# Adding New Files to Xcode Project

The following files need to be added to the VoiceControl.xcodeproj:

1. **VoiceControl/Core/AudioPreprocessor.swift**
2. **VoiceControl/Core/VADSilenceDetector.swift**

## Steps to Add Files:

1. Open VoiceControl.xcodeproj in Xcode
2. In the project navigator (left sidebar), right-click on the "Core" folder
3. Select "Add Files to VoiceControl..."
4. Navigate to VoiceControl/Core/
5. Select both:
   - AudioPreprocessor.swift
   - VADSilenceDetector.swift
6. Make sure "Copy items if needed" is unchecked (files are already in place)
7. Make sure "VoiceControl" target is checked
8. Click "Add"

## Alternative: Command Line Build Without New Files

For testing without the VAD implementation, you can temporarily disable VAD in Config.swift by setting:
```swift
static let vadEnabled = false
```

This will use the existing DynamicSilenceDetector instead.