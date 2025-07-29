# Edit Mode Direct Accessibility API Design Spec

## Overview
This spec outlines the redesign of Edit Mode to use direct macOS Accessibility API manipulation instead of keyboard simulation. Based on research into how VoiceOver, Dictation, and Switch Control work, we'll implement a fast, reliable text editing system that works across all apps.

## Current Issues
1. **Slow and clunky**: Current implementation uses keyboard shortcuts (Cmd+F, typing, etc.)
2. **Unreliable selection**: Text selection via keyboard shortcuts can fail
3. **Limited context**: Only works with selected text, doesn't consider cursor position
4. **Poor UX**: Visible UI actions (find dialog) disrupt user experience

## Key Insights from Research
- **Cannot call insertText:** When editing from an overlay tool, we can't call insertText: on foreign NSTextView
- **Use AX APIs:** Must use Accessibility APIs that apps expose to automation tools
- **Atomic operations:** Single AX "set" fires OS-level notifications for instant updates
- **Fallback strategy:** Some apps (Word, Electron) reject direct value sets - use pasteboard

## Implementation Strategy

### Primary Approach: Direct AX Editing
```swift
func replaceSelectionWithCorrectedText(_ corrected: String) {
    let sysWide = AXUIElementCreateSystemWide()
    
    // 1. Get focused element
    var focused: AXUIElement?
    guard AXUIElementCopyAttributeValue(
        sysWide,
        kAXFocusedUIElementAttribute as CFString,
        &focused) == .success,
          let element = focused
    else { return }

    // 2. Try direct replacement via selected-range/value attributes
    var rangeValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &rangeValue) == .success,
       let axVal = rangeValue as? AXValue,
       axVal.axValueType == .cfRange {

        // a) Replace the value of the selection
        AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString,
            corrected as CFTypeRef)

        // b) Update the selection so the new text stays highlighted
        var newRange = CFRangeMake(
            CFRange(location: 0, length: corrected.utf16.count).location,
            corrected.utf16.count)
        let newAXRange = AXValueCreate(.cfRange, &newRange)!
        AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString,
            newAXRange)
        return  // ✅ done in one shot
    }

    // 3. Fallback: pasteboard + ⌘V for stubborn apps
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(corrected, forType: .string)
    
    // Simulate Cmd+V
    if let src = CGEventSource(stateID: .hidSystemState) {
        let keyDown = CGEvent(keyboardEventSource: src,
                              virtualKey: CGKeyCode(kVK_ANSI_V),
                              keyDown: true)!
        keyDown.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src,
                            virtualKey: CGKeyCode(kVK_ANSI_V),
                            keyDown: false)!
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

### Enhanced Context Detection
For better UX, we'll still implement context detection when no text is selected:

```swift
func getEditContext() throws -> EditContext {
    let sysWide = AXUIElementCreateSystemWide()
    var focused: AXUIElement?
    
    guard AXUIElementCopyAttributeValue(
        sysWide,
        kAXFocusedUIElementAttribute as CFString,
        &focused) == .success,
        let element = focused
    else { throw AccessibilityError.noFocusedElement }
    
    // Check for selected text first
    var selectedText: CFTypeRef?
    if AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextAttribute as CFString,
        &selectedText) == .success,
       let text = selectedText as? String,
       !text.isEmpty {
        
        // Get the range for later replacement
        var rangeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue)
        
        return .selectedText(text)
    }
    
    // No selection - get cursor position and surrounding context
    var rangeValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &rangeValue) == .success,
       let axVal = rangeValue as? AXValue {
        
        var cfRange = CFRange()
        AXValueGetValue(axVal, .cfRange, &cfRange)
        
        // Get full text to find paragraph around cursor
        var fullValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &fullValue) == .success,
           let fullText = fullValue as? String {
            
            let paragraph = extractParagraphAroundPosition(
                fullText,
                position: cfRange.location
            )
            
            return .paragraphAroundCursor(paragraph)
        }
    }
    
    throw AccessibilityError.cannotDetermineContext
}
```

## App Compatibility Matrix

| App Type | Direct AX Set | Fallback Needed | Notes |
|----------|---------------|-----------------|-------|
| Native NSTextView | ✅ | No | Works perfectly |
| Safari/WebKit | ✅ | No | Full AX support |
| VS Code | ✅ | No | Monaco editor supports AX |
| Microsoft Word | ❌ | Yes | Use pasteboard |
| Electron Apps | ❌ | Yes | Most reject direct sets |
| React Native | ❌ | Yes | Limited AX support |

## Benefits Over Current Implementation

1. **Speed**: <100ms response time (vs ~500ms with keyboard simulation)
2. **Reliability**: No dependency on UI state or find dialogs
3. **Universal**: Works across all apps with graceful fallback
4. **Atomic**: Single operation = single accessibility notification
5. **VoiceOver Compatible**: Proper notifications keep screen readers in sync

## Implementation Plan

### Phase 1: Core Replacement Function
- [ ] Implement `replaceSelectionWithCorrectedText()` 
- [ ] Add fallback to pasteboard strategy
- [ ] Test with common apps

### Phase 2: Context Enhancement
- [ ] Implement `getEditContext()` for no-selection scenarios
- [ ] Add paragraph extraction logic
- [ ] Handle edge cases (empty text, cursor at boundaries)

### Phase 3: Integration
- [ ] Update EditManager to use new methods
- [ ] Remove old keyboard simulation code
- [ ] Update error handling for AX-specific errors

### Phase 4: Polish
- [ ] Add optional VoiceOver announcements
- [ ] Performance logging
- [ ] Handle permission errors gracefully

## Security & Permissions

1. **Accessibility Permission**: Required (System Settings > Privacy & Security > Accessibility)
3. **Sandboxing**: Cannot be sandboxed for Mac App Store distribution
4. **Distribution**: Must be notarized for distribution outside App Store

## Success Criteria

1. Instant text replacement (<100ms)
2. Works in 90%+ of common apps
3. Graceful fallback for stubborn apps
4. Maintains selection/cursor position
5. VoiceOver announces changes correctly
6. No visible UI disruptions

## Error Handling

```swift
enum AccessibilityError: Error {
    case noFocusedElement
    case cannotGetSelection
    case cannotSetValue
    case fallbackFailed
    case noAccessibilityPermission
}

func handleAccessibilityError(_ error: AccessibilityError) {
    switch error {
    case .noFocusedElement:
        // Show HUD: "Please click in a text field"
    case .cannotSetValue:
        // Automatic fallback to pasteboard
    case .fallbackFailed:
        // Show HUD: "Unable to edit text in this app"
    // etc...
    }
}
```

## Testing Checklist

- [ ] Native apps (TextEdit, Notes)
- [ ] Web browsers (Safari, Chrome, Firefox)
- [ ] Code editors (VS Code, Xcode)
- [ ] Microsoft Office apps
- [ ] Electron apps (Slack, Discord)
- [ ] Web apps in various frameworks
- [ ] VoiceOver compatibility
- [ ] Multi-monitor setups
- [ ] Different text encodings

## References

- [Apple Accessibility Programming Guide](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/)
- VoiceOver implementation patterns
- Switch Control text manipulation
- macOS Dictation internal behaviors