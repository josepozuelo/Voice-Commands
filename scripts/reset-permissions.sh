#!/bin/bash

# Reset permissions for VoiceControl app
# This is needed because macOS tracks permissions by app signature,
# which changes with each build

echo "🔄 Resetting permissions for VoiceControl..."

# Reset all permissions
tccutil reset Accessibility com.yourteam.VoiceControl 2>/dev/null || true
tccutil reset ListenEvent com.yourteam.VoiceControl 2>/dev/null || true
tccutil reset PostEvent com.yourteam.VoiceControl 2>/dev/null || true
tccutil reset Microphone com.yourteam.VoiceControl 2>/dev/null || true

echo "✅ Permissions reset complete"