# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoiceControl is a macOS voice command app built with SwiftUI that enables hands-free text manipulation. It uses OpenAI's Whisper API for speech recognition and macOS Accessibility APIs for text control.

## Workflow
- First think through the problem, read the codebase for relevant files and ask any questions or do any research you might need.
- You will then plan out the feature or task at hand, if the feature needs some high-level definition and design, you can create a spec in the spec folder, so that I can review and work through it with you. If the feature is well defined or straightforward you can skip to the next step.
- You will use the todo.md file in the tasks folder to have an implementation plan with the specific todos you need to execute on. I will be able to collaborate with you in that file. 
- Once I give you the greenlight you can start implementing and start checking off the todo items as you go. 
- Commit your work when you think it's a good checkpoint. 

## Development Commands

### Build and Run
- Open project: `open VoiceControl.xcodeproj`
- Build in Xcode: ⌘B or Product → Build
- Run in Xcode: ⌘R or Product → Run

### Environment Setup
- Required environment variable: `OPENAI_API_KEY`
- Add to shell profile: `export OPENAI_API_KEY="your-api-key-here"`
- Minimum macOS: 13.0+ (Ventura)
- Minimum Xcode: 15.0+

### Release Build and Installation
Every time you build a new release for testing, follow these steps:

1. Kill any running instances: `pkill -f VoiceControl`
2. Build release: `xcodebuild -project VoiceControl.xcodeproj -scheme VoiceControl -configuration Release -derivedDataPath build clean build`
3. Install to Applications: `cp -R "build/Build/Products/Release/VoiceControl.app" /Applications/`
4. Reset all permissions:
   - `tccutil reset Accessibility com.yourteam.VoiceControl`
   - `tccutil reset ListenEvent com.yourteam.VoiceControl`
   - `tccutil reset PostEvent com.yourteam.VoiceControl`
5. Sign the app: `codesign --force --deep --sign - /Applications/VoiceControl.app`
6. Launch `/Applications/VoiceControl.app` and grant all permissions when prompted

**Note**: The permission reset is necessary because macOS tracks permissions by app signature, which changes with each build.

### Required Permissions
The app requires these macOS permissions:
1. Microphone Access (for voice recognition)
2. Accessibility Access (for text manipulation)
3. Input Monitoring (for global hotkeys)

## Architecture

### Core System Flow
1. **HotkeyManager** detects ⌃⇧V (Control+Shift+V) global hotkey
2. **AudioEngine** captures microphone input and processes audio
3. **WhisperService** sends audio to OpenAI Whisper API for transcription
4. **CommandMatcher** performs fuzzy matching against commands in `commands.json`
5. **CommandManager** orchestrates the workflow and decides execution vs. disambiguation
6. **CommandHUD** displays visual feedback and disambiguation UI when needed
7. **AccessibilityBridge** executes the final text manipulation via AXUIElement APIs

### Key Components

- **VoiceControlApp.swift**: Main app entry point, sets up as accessory app with hidden window
- **Config/Config.swift**: Centralized configuration including API keys, hotkey codes, and thresholds
- **Core/AudioEngine.swift**: Microphone capture and audio processing
- **Core/WhisperService.swift**: OpenAI Whisper API integration for speech-to-text
- **Core/AccessibilityBridge.swift**: Text manipulation via macOS Accessibility APIs
- **Features/Command/CommandManager.swift**: Workflow orchestration and state management
- **Features/Command/CommandMatcher.swift**: Fuzzy matching algorithm with confidence scoring
- **Features/Command/CommandHUD.swift**: Visual feedback and disambiguation interface
- **Models/Command.swift**: Command data structures and JSON parsing
- **Resources/commands.json**: Command definitions with phrases and actions
- **Utils/HotkeyManager.swift**: Global hotkey registration and detection
- **Utils/TextSelection.swift**: Text selection utilities and boundary detection

### Command System

Commands are defined in `Resources/commands.json` with:
- **phrases**: Array of voice trigger phrases
- **action**: Action type and parameters (selectText, systemAction, moveCursor)
- **category**: Grouping (textSelection, system, navigation, editing)

The fuzzy matching system uses confidence scoring (threshold: 0.85) to decide between:
- Auto-execution for high-confidence matches
- Disambiguation HUD for multiple possible matches

### Global Hotkeys
- **⌃⇧V**: Voice Commands (implemented)
- **⌥⌘D**: Dictation Mode (future feature)
- **⌥⌘E**: Edit Mode (future feature)

## Adding New Commands

1. Edit `VoiceControl/Resources/commands.json`
2. Add new command object with required fields: id, phrases, action, category
3. Rebuild project to include changes
4. Test with target applications (TextEdit, Safari, VS Code, etc.)

Action types:
- `selectText`: Text selection with selectionType (word, sentence, paragraph, etc.)
- `systemAction`: Keyboard shortcuts with key combinations
- `moveCursor`: Cursor movement with direction and unit parameters