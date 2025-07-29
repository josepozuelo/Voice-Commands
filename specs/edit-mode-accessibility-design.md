# Edit Mode Design Document

## Overview

Edit Mode is a powerful feature in VoiceControl that allows users to edit text using voice commands. It captures the current text context (selected text, paragraph, or entire document), records voice instructions, uses GPT to apply the edits, and then replaces the original text using macOS Accessibility APIs.

## Architecture

### Key Components

1. **EditManager** (`CommandManager.swift`)
   - Orchestrates the edit workflow
   - Manages UI state and user interaction
   - Handles audio recording and processing

2. **AccessibilityBridge** (`AccessibilityBridge.swift`)
   - Interfaces with macOS Accessibility APIs
   - Handles text context detection and replacement
   - Provides smart text manipulation without keyboard simulation

3. **WhisperService** - Transcribes voice instructions
4. **GPTService** - Processes edit instructions and generates corrected text

## Workflow

### 1. Activation
- User presses **⌃⇧E** (Control+Shift+E) hotkey
- EditManager transitions from `.idle` to `.selecting` state

### 2. Context Detection
The system determines what text to edit by calling `accessibilityBridge.getEditContext()`:

```swift
enum EditContext {
    case selectedText(String)                      // User has text selected
    case paragraphAroundCursor(String, NSRange)    // No selection, edit paragraph
    case entireDocument(String)                    // Edit entire document
}
```

#### Context Detection Logic:
1. **Check for Selected Text**: Query `kAXSelectedTextAttribute`
2. **No Selection**: Get cursor position via `kAXSelectedTextRangeAttribute`
3. **Extract Paragraph**: Find paragraph boundaries around cursor position
4. **Fallback**: Use entire document if paragraph detection fails

### 3. Voice Recording
- Transitions to `.recording` state
- Records up to 30 seconds of audio
- No silence detection (user manually stops with ⌃⇧E)

### 4. Processing
- Transcribe audio using Whisper API
- Send original text + instructions to GPT-4
- GPT returns edited version of the text

### 5. Text Replacement
- Transitions to `.replacing` state
- Uses `replaceSelectionWithCorrectedText()` with the edit context

## Accessibility API Implementation

### Smart Text Replacement

The system uses a sophisticated approach that avoids keyboard simulation:

#### For Selected Text:
```swift
case .selectedText(let originalText):
    // Simple paste operation since text is already selected
    pasteText(corrected)
```

#### For Paragraph Editing (Smart Approach):
```swift
case .paragraphAroundCursor(let originalText, let range):
    // Direct API manipulation without selection
    try replaceTextInRange(range, with: corrected, in: axElement)
```

The `replaceTextInRange` method:
1. Gets full document text via `kAXValueAttribute`
2. Replaces text at specific NSRange
3. Sets entire document back via `AXUIElementSetAttributeValue`
4. Positions cursor at end of replaced text

#### For Entire Document:
```swift
case .entireDocument(_):
    // Direct value replacement
    AXUIElementSetAttributeValue(axElement, kAXValueAttribute, corrected)
```

### Key Accessibility APIs Used

1. **Getting Focused Element**
   ```swift
   AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focused)
   ```

2. **Reading Text Content**
   - `kAXSelectedTextAttribute` - Currently selected text
   - `kAXValueAttribute` - Full text content
   - `kAXSelectedTextRangeAttribute` - Cursor position/selection range

3. **Writing Text Content**
   - `AXUIElementSetAttributeValue(element, kAXValueAttribute, newText)`
   - `AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute, newText)`

4. **Cursor Management**
   ```swift
   var cfRange = CFRange(location: position, length: 0)
   let axRange = AXValueCreate(.cfRange, &cfRange)
   AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute, axRange)
   ```

### Paragraph Detection Algorithm

When no text is selected, the system intelligently detects paragraph boundaries:

```swift
func extractParagraphAroundPosition(_ text: String, position: Int) -> (String, NSRange) {
    // Search backwards for paragraph start (double newline or start)
    while start > 0 {
        if text[start-1] == '\n' && start > 1 && text[start-2] == '\n' {
            break  // Found paragraph boundary
        }
        start -= 1
    }
    
    // Search forwards for paragraph end (double newline or end)
    while end < text.length {
        if text[end] == '\n' && end+1 < text.length && text[end+1] == '\n' {
            break  // Found paragraph boundary
        }
        end += 1
    }
}
```

### Fallback Strategies

If direct AX API manipulation fails, the system falls back to:

1. **Selection + Paste Method**:
   - `selectParagraph()` - Uses ⌥↑ then ⌥⇧↓ keyboard simulation
   - `pasteText()` - Copies to pasteboard and simulates ⌘V

2. **Error Handling**:
   - Graceful degradation with informative error messages
   - Automatic state reset after errors

## Benefits of This Approach

1. **No Visual Selection Artifacts**: Direct API manipulation is invisible to the user
2. **App Compatibility**: Works with any app supporting macOS Accessibility
3. **Accurate Positioning**: Maintains exact cursor position after edits
4. **Performance**: Faster than keyboard simulation
5. **Reliability**: Avoids conflicts with app-specific keyboard shortcuts

## Technical Considerations

### Permissions Required
- Accessibility permission for AXUIElement access
- Required for both reading and writing text content

### Limitations
1. Some apps may not fully implement AX APIs
2. Web-based editors might have limited support
3. Fallback to keyboard simulation may be needed

### Performance Notes
- Direct API calls are synchronous and fast
- Small delays (50-100ms) used for keyboard simulation fallback
- Pasteboard contents are preserved and restored

## Future Enhancements

1. **Multi-paragraph Support**: Edit multiple paragraphs in one command
2. **Streaming Edits**: Show edits as they're being processed
3. **Undo Support**: Track edit history for reversal
4. **Smart Selection**: Better context detection for code, lists, etc.
5. **Batch Operations**: Apply same edit to multiple selections

## Example Usage

1. User places cursor in a paragraph
2. Presses ⌃⇧E to start Edit Mode
3. Says "Fix the grammar and make it more concise"
4. Presses ⌃⇧E to stop recording
5. System replaces the paragraph with the edited version
6. Cursor is positioned at the end of the new text

The entire operation happens without visible text selection or keyboard shortcuts, providing a seamless editing experience.