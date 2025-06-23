# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoiceControl is a macOS voice command app built with SwiftUI that enables hands-free text manipulation. It uses OpenAI's Whisper API for speech recognition and macOS Accessibility APIs for text control. Features continuous voice command mode with automatic silence detection and voice-based disambiguation.

**Bundle Identifier**: com.yourteam.VoiceControl  
**Minimum Requirements**: macOS 13.0+, Xcode 15.0+, Swift 5.0

## Development Workflow

1. **Analyze**: Read relevant code, understand the problem
2. **Design** (if needed): Create spec in `specs/` folder for complex features
3. **Plan**: Use `tasks/todo.md` to list implementation steps
4. **Implement**: Execute tasks after approval, check off items as completed
5. **Commit**: Create commits at logical checkpoints 

## Development Commands



### Environment Setup
- Required environment variable: `OPENAI_API_KEY`
- Add to shell profile: `export OPENAI_API_KEY="your-api-key-here"`
- Minimum macOS: 13.0+ (Ventura)
- Minimum Xcode: 15.0+

### Release Build and Installation
Every time you build a new release for testing, follow these steps:

- Use a add_files_simple.py to make sure your xcode configuration is up to date

**Note**: The permission reset is necessary because macOS tracks permissions by app signature, which changes with each build.

### Required Permissions
The app requires these macOS permissions:
1. Microphone Access (for voice recognition)
2. Accessibility Access (for text manipulation)
3. Input Monitoring (for global hotkeys)

## Architecture

### Core System Flow
1. **HotkeyManager** detects ⌃⇧V (Control+Shift+V) global hotkey
2. **AudioEngine** captures microphone input with silence detection for continuous mode
3. **WhisperService** sends audio to OpenAI Whisper API for transcription
4. **CommandMatcher** performs fuzzy matching against commands in `commands.json`
5. **CommandManager** orchestrates workflow, handles continuous mode and voice disambiguation
6. **CommandHUD** displays visual feedback, continuous mode indicator, and voice-enabled disambiguation
7. **AccessibilityBridge** executes the final text manipulation via AXUIElement APIs

### Key Components

- **VoiceControlApp.swift**: Main app entry point, sets up as accessory app with hidden window
- **Config/Config.swift**: Centralized configuration including API keys, hotkey codes, thresholds, and continuous mode settings
- **Core/AudioEngine.swift**: Microphone capture, audio processing, and silence detection for continuous mode
- **Core/WhisperService.swift**: OpenAI Whisper API integration for speech-to-text
- **Core/AccessibilityBridge.swift**: Text manipulation via macOS Accessibility APIs
- **Features/Command/CommandManager.swift**: Workflow orchestration, continuous mode management, and voice disambiguation
- **Features/Command/CommandMatcher.swift**: Fuzzy matching algorithm with confidence scoring
- **Features/Command/CommandHUD.swift**: Visual feedback, continuous mode UI, and voice-enabled disambiguation
- **Models/Command.swift**: Command data structures and JSON parsing
- **Resources/commands.json**: Command definitions with phrases and actions
- **Utils/HotkeyManager.swift**: Global hotkey registration and detection
- **Utils/TextSelection.swift**: Text selection utilities and boundary detection
- **Utils/CircularBuffer.swift**: Audio buffer implementation for continuous capture