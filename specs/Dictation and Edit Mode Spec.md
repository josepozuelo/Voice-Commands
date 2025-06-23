# Dictation and Edit Mode Design Specification

## Overview

In addition to voice commands, we also want to have other two modes: 
1. **Dictation Mode** - Long-form speech-to-text transcription
2. **Edit Mode** - AI-powered text editing via voice instructions

Both modes use explicit start/stop control (no automatic silence detection) and leverage OpenAI's Whisper API for transcription and GPT-4 for text transformation.

## User Interface

### HUD Design

The HUD will display two primary action buttons when idle, in addition to the Voice Commands button:

```
┌─────────────────────────────────────────┐
│  🎙️ VoiceControl                        │
│                                         │
│  [📝 Dictation]  [✏️ Edit]             │
│   ⌥⌘D           ⌥⌘E                    │
└─────────────────────────────────────────┘
```

### Visual States (Make them compatible with Voice commands HUD states)

1. **Idle State**: Shows two buttons with hotkey hints
2. **Recording State**: Shows recording indicator, elapsed time, stop button
3. **Processing State**: Shows progress indicator while transcribing/processing
4. **Error State**: Shows error message with retry option

## Dictation Mode

### Workflow

1. **Start Recording**
   - User presses ⌥⌘D or clicks Dictation button
   - AudioEngine starts recording (no silence detection)
   - HUD shows recording state with elapsed time
   - Maximum recording duration: 10 minutes

2. **Stop Recording**
   - User presses ⌥⌘D again or clicks Stop button
   - Recording stops immediately
   - Audio data sent to Whisper API

3. **Transcription**
   - HUD shows processing state
   - Whisper returns transcribed text
   - Send text to GPT 4.1 mini with a simple prompt to lightly format the dictated text without changing anything of substance. (add a flag to be able to turn this off)
   - Text is inserted at current cursor position

4. **Cancellation**
   - Press Esc or click X to cancel recording
   - No transcription performed
   - Returns to idle state

### Technical Implementation

```swift
// DictationManager states
enum DictationState {
    case idle
    case recording(startTime: Date)
    case processing
    case error(Error)
}

// Key methods
func startDictation()
func stopDictation()
func cancelDictation()
```

## Edit Mode

### Workflow

1. **Check Selection**
   - User presses ⌥⌘E or clicks Edit button
   - System checks for selected text via AccessibilityBridge
   - If no selection: automatically select current paragraph
   - Store selected text and position

2. **Record Instructions**
   - Start recording voice instructions
   - HUD shows recording state with selected text preview
   - User speaks editing instructions

3. **Stop and Process**
   - User presses ⌥⌘E again or clicks Stop
   - Recording stops
   - Audio sent to Whisper for transcription

4. **AI Processing**
   - Prompt + Transcribed instructions + selected text sent to GPT-4.1-mini
   - Custom prompt instructs GPT to edit the text
   - Returns edited version

5. **Text Replacement**
   - Find and replace original text with edited version
   - Maintain cursor position
   - Show success feedback

### GPT Prompt Template

```
You are tasked with correcting dictation errors from speech-to-text output. The correction instructions you receive are also dictated and may contain errors.
	•	Only apply corrections that the user explicitly requests (for example, fixing a specific word or phrase that was transcribed incorrectly).
	•	Do not change form, style, arrangement, punctuation, or any other aspect of the text unless it directly addresses a dictation error mentioned by the user.
	•	When the user wants to correct spelling, they will say “spelled…” followed by example words that start with each letter. For instance, “spelled: Apple, Dog, Cat” means the intended letters are “A,” “D,” and “C.” There will be no explicit “end spelling” cue, so infer when the spelling sequence stops.

Do not make any additions or stylistic edits beyond the exact dictation corrections the user specifies.

Original message: " 
i was walking threw the park with my dog charley when we saw mr thompson or maybe mrs thomson i cant remember then dumbass and suresh showed up they said something about checking out the new diner downtown charly barked at a squirrel and almost pulled the leesh out of my hand kind of annoying cause i just bought it last weak dumbass also said the train was late again
"

Edit prompt: "can you fix this up it’s not dumbass it’s a spanish name spelled tomato or mom alter serve and it’s not suresh it’s spelled sample under radio alter jersey also fix the wrong words like threw which makes no sense in that context same with weak and add punctuation where it makes sense and split up the run-ons thanks. Capitalize sentence starts please"

Output the corrected_message as a a json property. 
```

## Error Handling

### Recording Errors
- Microphone permission denied → Show settings instructions
- Recording failure → Offer retry
- Maximum duration exceeded → Auto-stop and process

### API Errors
- Network timeout → Show offline message
- API rate limit → Show cooldown message
- Invalid API key → Show configuration instructions

### Text Manipulation Errors
- No accessible text field → Show helpful message
- Selection failed → Fallback to manual selection prompt
- Replacement failed → Show error with original text preserved

## HUD State Transitions

### Dictation Mode
```
Idle → Recording → Processing → Idle
 ↓         ↓           ↓
Error ← Cancel ← Network Error
```

### Edit Mode
```
Idle → Selecting → Recording → Processing → Replacing → Idle
 ↓         ↓           ↓            ↓            ↓
Error ← Cancel ← Cancel ← API Error ← Replace Error
```

## Implementation Plan - Edit Mode

### Phase 1: Core Infrastructure Setup
1. **Create EditManager.swift** ✅
   - Define EditState enum (idle, selecting, recording, processing, replacing, error) ✅
   - Implement state management similar to CommandManager ✅
   - Add properties for selected text storage and cursor position ✅

2. **Update Config.swift** ✅
   - Add Edit Mode hotkey configuration (⌥⌘E) ✅
   - Add GPT API configuration (model, max tokens, temperature) ✅
   - Add Edit Mode specific settings (auto-select paragraph, max recording duration) ✅

3. **Create GPTService.swift** ✅
   - Implement OpenAI GPT API integration ✅
   - Create edit prompt template method ✅
   - Handle JSON response parsing for corrected text ✅
   - Add error handling for API failures ✅

### Phase 2: Text Selection Enhancement
1. **Enhance AccessibilityBridge.swift** ✅
   - Add `hasTextSelection()` method to check if text is currently selected ✅
   - Add `selectParagraphIfNoSelection()` method that uses existing `selectParagraph()` ✅
   - Enhance `getCurrentSelection()` to store original text for later verification ✅
   - Add `replaceText(originalText:newText:)` method for smart replacement ✅
   - Handle edge cases (text changed during editing, multiple matches) ✅

### Phase 3: HUD Integration
1. **Update CommandHUD.swift** ✅
   - Add Edit Mode button to idle state ✅
   - Create recording state UI for Edit Mode ✅
   - Add selected text preview display ✅
   - Implement processing state with appropriate messaging ✅

2. **Create EditModeHUD.swift** ✅
   - Build dedicated view for Edit Mode states ✅
   - Show selected text preview during recording ✅
   - Display processing status and error messages ✅
   - Add cancel functionality with Esc key support ✅

### Phase 4: Audio Recording Integration
1. **Update AudioEngine.swift** ✅
   - Add Edit Mode recording configuration (no silence detection) ✅
   - Implement maximum duration enforcement (10 minutes) ✅
   - Add recording state callbacks for UI updates ✅

2. **Update HotkeyManager.swift** ✅
   - Register ⌥⌘E hotkey for Edit Mode ✅
   - Handle toggle behavior (start/stop with same key) ✅
   - Coordinate with EditManager for state transitions ✅

### Phase 5: Workflow Implementation
1. **Implement EditManager Workflow** ✅
   - startEditing(): Check selection, auto-select if needed, start recording ✅
   - stopEditing(): Stop recording, transcribe, process with GPT ✅
   - cancelEditing(): Clean up state, restore UI ✅
   - processEditingInstructions(): Coordinate Whisper → GPT → Replace flow ✅

2. **Error Handling** ✅
   - Handle no accessible text field scenarios ✅
   - Manage API failures with user-friendly messages ✅
   - Implement retry mechanisms where appropriate ✅
   - Preserve original text on failure ✅

2. **Update HUD for Dictation**
   - Add Dictation button
   - Implement dictation-specific recording view
   - Share processing states with Edit Mode