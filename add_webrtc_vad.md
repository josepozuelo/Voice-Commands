# Adding WebRTC VAD Package to VoiceControl

To add the WebRTC VAD Swift Package to the project:

1. Open VoiceControl.xcodeproj in Xcode
2. In Xcode, go to File → Add Package Dependencies...
3. Enter the package URL: `https://github.com/dabrahams/webrtcvad.git`
4. Set the version rule to "Up to Next Major Version" from 1.0.0
5. Click "Add Package"
6. Select "WebRTCVAD" library and add it to the VoiceControl target
7. Click "Add Package"

The package will be added to your project and available for import.

Note: After adding the package, you'll need to import it in your Swift files with:
```swift
import WebRTCVAD
```