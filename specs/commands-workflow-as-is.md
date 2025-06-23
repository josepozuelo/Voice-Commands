# Commands Workflow As-Is

This document describes the current implementation of the voice command system in VoiceControl, with a focus on how commands are processed from speech input to execution.

## Overview

The voice command system processes user speech through several stages:
1. Audio capture and transcription
2. Command classification using LLM
3. Command routing based on intent
4. Execution via macOS Accessibility APIs

## Command Flow

### 1. Command Definition (`commands.json`)

Commands are defined in a JSON structure with the following properties:
- `id`: Unique identifier
- `phrases`: Array of voice triggers that match this command
- `action`: Object containing `type` and type-specific parameters
- `category`: Command grouping (textSelection, system, navigation, editing)

Example select command:
```json
{
  "id": "select_word",
  "phrases": ["select word", "highlight word", "select the word"],
  "action": {
    "type": "selectText",
    "selectionType": "word"
  },
  "category": "textSelection"
}
```

### 2. Audio Processing and Transcription

When the user presses the hotkey (⌃⇧V):
1. `CommandManager` starts listening via `AudioEngine`
2. Audio is captured and sent to `WhisperService`
3. Whisper API returns transcribed text

### 3. Command Classification (`CommandManager.swift:259`)

The transcribed text is processed:
```swift
private func classifyAndExecute(_ text: String) {
    lastTranscription = text
    hudState = .classifying
    
    Task {
        let command = try await commandClassifier.classify(text)
        // Command is now a CommandJSON object with intent and parameters
    }
}
```

The `CommandClassifier` uses an LLM to:
- Match the transcription to command phrases
- Extract parameters (count, direction, etc.)
- Return a structured `CommandJSON` object

### 4. Command Routing (`CommandRouter.swift:16`)

The router receives the classified command and routes based on intent:
```swift
func route(_ command: CommandJSON) async throws {
    switch command.intent {
    case .shortcut:
        try await routeShortcut(command)
    case .select:
        try await routeSelect(command)  // Line 24
    case .move:
        try await routeMove(command)
    // ... other intents
    }
}
```

### 5. Select Command Processing (`CommandRouter.swift:102-150`)

For select commands, the router:

1. **Extracts Parameters**:
   - `unit`: What to select (word, sentence, paragraph, etc.)
   - `direction`: Which instance (this/next/prev), defaults to "this"
   - `count`: How many units, defaults to 1

2. **Maps to Selection Type**:
   ```swift
   let selectionType: SelectionType
   switch unit {
   case .word:
       selectionType = .word
   case .sentence:
       selectionType = .sentence
   case .paragraph:
       selectionType = .paragraph
   case .line:
       selectionType = .line
   case .all:
       selectionType = .all
   }
   ```

3. **Handles Direction**:
   - `this`: Selects current unit
   - `next`: Selects next unit(s) (TODO: not fully implemented)
   - `prev`: Selects previous unit(s) (TODO: not fully implemented)

### 6. Accessibility Bridge Execution (`AccessibilityBridge.swift:81-115`)

The `AccessibilityBridge` performs the actual selection using macOS keyboard shortcuts:

```swift
func selectText(matching pattern: SelectionType) throws {
    switch pattern {
    case .word:
        // Option+Shift+RightArrow
        simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.option, .shift])
    
    case .sentence:
        // Custom logic: searches for punctuation boundaries
        try selectSentence()
    
    case .paragraph:
        // Option+Up, then Option+Shift+Down
        simulateKeyCommand(key: CGKeyCode(kVK_UpArrow), modifiers: [.option])
        simulateKeyCommand(key: CGKeyCode(kVK_DownArrow), modifiers: [.option, .shift])
    
    case .line:
        // Cmd+Right, then Cmd+Shift+Left
        simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.command])
        simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.command, .shift])
    
    case .all:
        // Cmd+A
        simulateKeyCommand(key: CGKeyCode(kVK_ANSI_A), modifiers: [.command])
    }
}
```

### 7. Special Selection Logic

#### Sentence Selection (`AccessibilityBridge.swift:168-192`)
1. Moves cursor to beginning of word (Option+Left)
2. Searches backwards for sentence punctuation (. ! ?)
3. Extends selection forward until next punctuation

#### Paragraph Selection (`AccessibilityBridge.swift:212-215`)
1. Moves to paragraph start (Option+Up)
2. Extends selection to paragraph end (Option+Shift+Down)

## Key Components Summary

- **CommandManager**: Orchestrates the workflow, manages state
- **CommandClassifier**: Uses LLM to match speech to commands
- **CommandRouter**: Routes commands to appropriate handlers based on intent
- **AccessibilityBridge**: Executes commands via macOS Accessibility APIs

## Current Limitations

1. Direction modifiers (next/prev) for select commands are not fully implemented
2. Character-level selection defaults to word selection
3. Sentence movement uses line movement as a fallback
4. Some complex selections rely on application-specific behavior of keyboard shortcuts