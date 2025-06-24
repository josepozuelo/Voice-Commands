import Foundation
import ApplicationServices
import Carbon
import AppKit

enum EditContext {
    case selectedText(String)
    case paragraphAroundCursor(String, NSRange)
    case entireDocument(String)
}

class AccessibilityBridge {
    enum AccessibilityError: LocalizedError {
        case noAccessibilityPermission
        case failedToGetFocusedElement
        case failedToPerformAction
        case unsupportedOperation
        case cannotDetermineContext
        case cannotGetSelection
        case cannotSetValue
        case fallbackFailed
        
        var errorDescription: String? {
            switch self {
            case .noAccessibilityPermission:
                return "Accessibility permission not granted. Please enable in System Settings > Privacy & Security > Accessibility."
            case .failedToGetFocusedElement:
                return "Could not get focused element"
            case .failedToPerformAction:
                return "Failed to perform accessibility action"
            case .unsupportedOperation:
                return "The current application doesn't support this operation"
            case .cannotDetermineContext:
                return "Cannot determine editing context"
            case .cannotGetSelection:
                return "Cannot get text selection"
            case .cannotSetValue:
                return "Cannot set text value"
            case .fallbackFailed:
                return "Fallback paste operation failed"
            }
        }
    }
    
    func hasTextSelection() async -> Bool {
        guard HotkeyManager.hasAccessibilityPermission() else {
            return false
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success,
              let element = focusedElement else {
            return false
        }
        
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        
        if textResult == .success,
           let text = selectedText as? String,
           !text.isEmpty {
            return true
        }
        
        return false
    }
    
    func selectParagraphIfNoSelection() async {
        let hasSelection = await hasTextSelection()
        if !hasSelection {
            try? selectParagraph()
        }
    }
    
    // Deprecated: Use replaceSelectionWithCorrectedText instead
    func replaceText(originalText: String, newText: String) async throws {
        // This method is deprecated in favor of direct AX manipulation
        // Keeping for backward compatibility but redirecting to new method
        try replaceSelectionWithCorrectedText(newText)
    }
    
    func getCurrentSelection() throws -> (text: String, range: NSRange)? {
        guard HotkeyManager.hasAccessibilityPermission() else {
            throw AccessibilityError.noAccessibilityPermission
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success,
              let element = focusedElement else {
            throw AccessibilityError.failedToGetFocusedElement
        }
        
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )
        
        if textResult == .success,
           let text = selectedText as? String,
           rangeResult == .success,
           let range = selectedRange {
            let cfRange = range as! AXValue
            var rangeValue = CFRange()
            AXValueGetValue(cfRange, .cfRange, &rangeValue)
            
            return (text, NSRange(location: rangeValue.location, length: rangeValue.length))
        }
        
        return nil
    }
    
    func replaceSelection(with text: String) throws {
        guard HotkeyManager.hasAccessibilityPermission() else {
            throw AccessibilityError.noAccessibilityPermission
        }
        
        simulateKeyboardInput(text)
    }
    
    func selectText(matching pattern: SelectionType) throws {
        guard HotkeyManager.hasAccessibilityPermission() else {
            throw AccessibilityError.noAccessibilityPermission
        }
        
        switch pattern {
        case .word:
            simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.option, .shift])
        case .previousWord:
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.option, .shift])
        case .nextWord:
            simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.option, .shift])
        case .sentence:
            try selectSentence()
        case .previousSentence:
            try selectPreviousSentence()
        case .nextSentence:
            // Move to next sentence
            simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [])
            try selectSentence()
        case .paragraph:
            try selectParagraph()
        case .previousParagraph:
            try selectPreviousParagraph()
        case .nextParagraph:
            // Move to next paragraph
            simulateKeyCommand(key: CGKeyCode(kVK_DownArrow), modifiers: [.option])
            try selectParagraph()
        case .line:
            simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.command])
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.command, .shift])
        case .all:
            simulateKeyCommand(key: CGKeyCode(kVK_ANSI_A), modifiers: [.command])
        case .toEndOfLine:
            simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.command, .shift])
        case .toStartOfLine:
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.command, .shift])
        case .toEndOfDocument:
            simulateKeyCommand(key: CGKeyCode(kVK_DownArrow), modifiers: [.command, .shift])
        case .toStartOfDocument:
            simulateKeyCommand(key: CGKeyCode(kVK_UpArrow), modifiers: [.command, .shift])
        case .lastWord:
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.option, .shift])
        case .lastSentence:
            try selectPreviousSentence()
        case .lastParagraph:
            try selectPreviousParagraph()
        }
    }
    
    func moveCursor(to direction: Direction, by unit: Unit) throws {
        guard HotkeyManager.hasAccessibilityPermission() else {
            throw AccessibilityError.noAccessibilityPermission
        }
        
        let keyCode: CGKeyCode
        var modifiers: CGEventFlags = []
        
        switch (direction, unit) {
        case (.left, .character):
            keyCode = CGKeyCode(kVK_LeftArrow)
        case (.right, .character):
            keyCode = CGKeyCode(kVK_RightArrow)
        case (.left, .word):
            keyCode = CGKeyCode(kVK_LeftArrow)
            modifiers = .maskAlternate
        case (.right, .word):
            keyCode = CGKeyCode(kVK_RightArrow)
            modifiers = .maskAlternate
        case (.up, .line):
            keyCode = CGKeyCode(kVK_UpArrow)
        case (.down, .line):
            keyCode = CGKeyCode(kVK_DownArrow)
        case (.beginning, .line):
            keyCode = CGKeyCode(kVK_LeftArrow)
            modifiers = .maskCommand
        case (.end, .line):
            keyCode = CGKeyCode(kVK_RightArrow)
            modifiers = .maskCommand
        case (.beginning, .document):
            keyCode = CGKeyCode(kVK_UpArrow)
            modifiers = .maskCommand
        case (.end, .document):
            keyCode = CGKeyCode(kVK_DownArrow)
            modifiers = .maskCommand
        default:
            throw AccessibilityError.unsupportedOperation
        }
        
        simulateKeyCommand(key: keyCode, modifiers: modifiers)
    }
    
    func executeSystemAction(_ keyCommand: String) throws {
        guard HotkeyManager.hasAccessibilityPermission() else {
            throw AccessibilityError.noAccessibilityPermission
        }
        
        let components = parseKeyCommand(keyCommand)
        simulateKeyCommand(key: components.keyCode, modifiers: components.modifiers)
    }
    
    private func selectSentence() throws {
        simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.option])
        
        var foundStart = false
        for _ in 0..<100 {
            if let selection = try? getCurrentSelection(),
               selection.text.hasSuffix(".") || selection.text.hasSuffix("!") || selection.text.hasSuffix("?") {
                foundStart = true
                break
            }
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.option, .shift])
        }
        
        if !foundStart {
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.command, .shift])
        }
        
        for _ in 0..<100 {
            simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.option, .shift])
            if let selection = try? getCurrentSelection(),
               selection.text.hasSuffix(".") || selection.text.hasSuffix("!") || selection.text.hasSuffix("?") {
                break
            }
        }
    }
    
    private func selectPreviousSentence() throws {
        simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [])
        
        for _ in 0..<2 {
            for _ in 0..<100 {
                simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.option])
                if let selection = try? getCurrentSelection(),
                   selection.text.hasSuffix(".") || selection.text.hasSuffix("!") || selection.text.hasSuffix("?") {
                    break
                }
            }
        }
        
        simulateKeyCommand(key: CGKeyCode(kVK_RightArrow), modifiers: [.option])
        
        try selectSentence()
    }
    
    func selectParagraph() throws {
        simulateKeyCommand(key: CGKeyCode(kVK_UpArrow), modifiers: [.option])
        simulateKeyCommand(key: CGKeyCode(kVK_DownArrow), modifiers: [.option, .shift])
    }
    
    private func selectPreviousParagraph() throws {
        simulateKeyCommand(key: CGKeyCode(kVK_UpArrow), modifiers: [.option])
        simulateKeyCommand(key: CGKeyCode(kVK_UpArrow), modifiers: [.option])
        simulateKeyCommand(key: CGKeyCode(kVK_DownArrow), modifiers: [.option, .shift])
    }
    
    private func simulateKeyCommand(key: CGKeyCode, modifiers: CGEventFlags) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
        
        keyDown?.flags = modifiers
        keyUp?.flags = modifiers
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        usleep(10000)
    }
    
    private func simulateKeyboardInput(_ text: String) {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            if let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [char.utf16.first!])
                event.post(tap: .cghidEventTap)
            }
            
            if let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [char.utf16.first!])
                event.post(tap: .cghidEventTap)
            }
        }
    }
    
    private func parseKeyCommand(_ command: String) -> (keyCode: CGKeyCode, modifiers: CGEventFlags) {
        var modifiers: CGEventFlags = []
        var key = command
        
        // Handle both Unicode symbols and text-based modifiers
        // First, handle text-based format (e.g., "cmd+c", "ctrl+shift+v")
        if command.contains("+") {
            let parts = command.lowercased().split(separator: "+")
            for part in parts.dropLast() { // All parts except the last are modifiers
                switch part {
                case "cmd", "command":
                    modifiers.insert(.maskCommand)
                case "ctrl", "control":
                    modifiers.insert(.maskControl)
                case "opt", "option", "alt":
                    modifiers.insert(.maskAlternate)
                case "shift":
                    modifiers.insert(.maskShift)
                default:
                    break
                }
            }
            key = String(parts.last ?? "")
        } else {
            // Handle Unicode symbols format
            if key.contains("⌘") {
                modifiers.insert(.maskCommand)
                key = key.replacingOccurrences(of: "⌘", with: "")
            }
            if key.contains("⌥") {
                modifiers.insert(.maskAlternate)
                key = key.replacingOccurrences(of: "⌥", with: "")
            }
            if key.contains("⌃") {
                modifiers.insert(.maskControl)
                key = key.replacingOccurrences(of: "⌃", with: "")
            }
            if key.contains("⇧") {
                modifiers.insert(.maskShift)
                key = key.replacingOccurrences(of: "⇧", with: "")
            }
        }
        
        let keyCode: CGKeyCode
        switch key.uppercased() {
        case "A": keyCode = CGKeyCode(kVK_ANSI_A)
        case "C": keyCode = CGKeyCode(kVK_ANSI_C)
        case "V": keyCode = CGKeyCode(kVK_ANSI_V)
        case "X": keyCode = CGKeyCode(kVK_ANSI_X)
        case "Z": keyCode = CGKeyCode(kVK_ANSI_Z)
        case "S": keyCode = CGKeyCode(kVK_ANSI_S)
        case "F": keyCode = CGKeyCode(kVK_ANSI_F)
        case "`": keyCode = CGKeyCode(kVK_ANSI_Grave)
        case "⇥", "TAB": keyCode = CGKeyCode(kVK_Tab)
        case "⌫", "DELETE": keyCode = CGKeyCode(kVK_Delete)
        default: keyCode = CGKeyCode(kVK_ANSI_A)
        }
        
        return (keyCode, modifiers)
    }
    
    static func requestAccessibilityPermission() -> Bool {
        // Use the reliable HotkeyManager method instead of the unreliable AXIsProcessTrusted
        return HotkeyManager.hasAccessibilityPermission()
    }
    
    // MARK: - Direct AX Text Replacement
    
    /// Replaces the user's current selection in ANY focused text control using direct AX APIs
    func replaceSelectionWithCorrectedText(_ corrected: String, editContext: EditContext? = nil) throws {
        print("DEBUG: AccessibilityBridge - Starting text replacement")
        print("DEBUG: AccessibilityBridge - Edit context: \(String(describing: editContext))")
        
        // Get the focused element first
        let sysWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(
            sysWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused) == .success,
            let element = focused else {
            print("DEBUG: AccessibilityBridge - Failed to get focused element")
            throw AccessibilityError.failedToGetFocusedElement
        }
        
        let axElement = element as! AXUIElement
        
        // For edit mode with context, we'll use a smart approach
        if let context = editContext {
            switch context {
            case .selectedText(let originalText):
                // User had text selected, just paste the replacement
                print("DEBUG: AccessibilityBridge - Replacing selected text directly")
                pasteText(corrected)
                return
                
            case .paragraphAroundCursor(let originalText, let range):
                // Use direct AX API to replace text at the specific range
                print("DEBUG: AccessibilityBridge - Using smart range replacement for paragraph")
                print("DEBUG: AccessibilityBridge - Range: location=\(range.location), length=\(range.length)")
                
                do {
                    try replaceTextInRange(range, with: corrected, in: axElement)
                    return
                } catch {
                    print("DEBUG: AccessibilityBridge - Smart replacement failed: \(error), falling back to selection method")
                    // Fallback to selection method
                    try selectParagraph()
                    usleep(100000) // 100ms delay for selection to complete
                    pasteText(corrected)
                    return
                }
                
            case .entireDocument(_):
                // Try direct replacement of entire value
                print("DEBUG: AccessibilityBridge - Replacing entire document via AX API")
                let setResult = AXUIElementSetAttributeValue(
                    axElement,
                    kAXValueAttribute as CFString,
                    corrected as CFTypeRef
                )
                
                if setResult == .success {
                    print("DEBUG: AccessibilityBridge - Successfully replaced entire document")
                    return
                } else {
                    print("DEBUG: AccessibilityBridge - Direct replacement failed, using selection method")
                    selectAll()
                    pasteText(corrected)
                    return
                }
            }
        }
        
        // Fallback to original behavior if no context
        
        print("DEBUG: AccessibilityBridge - Got focused element, attempting direct replacement")
        
        // 2. Try direct replacement via selected-range/value attributes
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue) == .success,
           let axVal = rangeValue {
            
            let axValue = axVal as! AXValue
            var cfRange = CFRange()
            let gotValue = AXValueGetValue(axValue, .cfRange, &cfRange)
            
            if gotValue {
                print("DEBUG: AccessibilityBridge - Got selection range: location=\(cfRange.location), length=\(cfRange.length)")
                
                // Check if we have an actual selection (length > 0)
                if cfRange.length > 0 {
                    // a) Replace the value of the selection
                    let setResult = AXUIElementSetAttributeValue(
                        axElement,
                        kAXSelectedTextAttribute as CFString,
                        corrected as CFTypeRef)
                    
                    if setResult == .success {
                        print("DEBUG: AccessibilityBridge - Successfully set selected text via AX API")
                        
                        // b) Update the selection so the new text stays highlighted
                        var newRange = CFRange(location: cfRange.location, length: corrected.utf16.count)
                        if let newAXRange = AXValueCreate(.cfRange, &newRange) {
                            AXUIElementSetAttributeValue(
                                axElement,
                                kAXSelectedTextRangeAttribute as CFString,
                                newAXRange)
                        }
                        
                        // Verify the change was applied
                        var verifyText: CFTypeRef?
                        if AXUIElementCopyAttributeValue(
                            axElement,
                            kAXSelectedTextAttribute as CFString,
                            &verifyText) == .success,
                           let newText = verifyText as? String {
                            print("DEBUG: AccessibilityBridge - Verified new selected text: '\(newText)'")
                        }
                        
                        return // ✅ Success!
                    } else {
                        print("DEBUG: AccessibilityBridge - Direct AX set failed with result: \(setResult.rawValue), trying fallback")
                    }
                } else {
                    print("DEBUG: AccessibilityBridge - No text selected (cursor position only), using fallback")
                }
            }
        }
        
        // 3. Fallback: pasteboard + ⌘V for apps that reject direct AX updates
        print("DEBUG: AccessibilityBridge - Using pasteboard fallback strategy")
        
        // Save current pasteboard contents
        let pasteboard = NSPasteboard.general
        let savedContents = pasteboard.string(forType: .string)
        
        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(corrected, forType: .string)
        
        // Keep accessibility focus on the element, then paste
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
            usleep(50000) // 50ms delay
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
            
            print("DEBUG: AccessibilityBridge - Executed paste command")
            
            // Restore original pasteboard contents after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let saved = savedContents {
                    pasteboard.clearContents()
                    pasteboard.setString(saved, forType: .string)
                }
            }
        } else {
            print("DEBUG: AccessibilityBridge - Failed to create event source for paste")
            throw AccessibilityError.fallbackFailed
        }
    }
    
    /// Gets the current editing context (selected text, paragraph around cursor, etc.)
    func getEditContext() throws -> EditContext {
        print("DEBUG: AccessibilityBridge - Getting edit context")
        
        let sysWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        
        guard AXUIElementCopyAttributeValue(
            sysWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused) == .success,
            let element = focused
        else {
            throw AccessibilityError.failedToGetFocusedElement
        }
        
        let axElement = element as! AXUIElement
        
        // Check for selected text first
        var selectedText: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText) == .success,
           let text = selectedText as? String,
           !text.isEmpty {
            print("DEBUG: AccessibilityBridge - Found selected text: '\(text)'")
            return .selectedText(text)
        }
        
        // No selection - get cursor position and surrounding context
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue) == .success,
           let axVal = rangeValue {
            
            let axValue = axVal as! AXValue
            var cfRange = CFRange()
            AXValueGetValue(axValue, .cfRange, &cfRange)
            
            print("DEBUG: AccessibilityBridge - Cursor at position: \(cfRange.location)")
            
            // Get full text to find paragraph around cursor
            var fullValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                axElement,
                kAXValueAttribute as CFString,
                &fullValue) == .success,
               let fullText = fullValue as? String {
                
                let (paragraph, paragraphRange) = extractParagraphAroundPosition(
                    fullText,
                    position: cfRange.location
                )
                
                print("DEBUG: AccessibilityBridge - Found paragraph around cursor: '\(paragraph)'")
                return .paragraphAroundCursor(paragraph, paragraphRange)
            }
        }
        
        print("DEBUG: AccessibilityBridge - Could not determine context")
        throw AccessibilityError.cannotDetermineContext
    }
    
    /// Extracts paragraph around given position in text
    private func extractParagraphAroundPosition(_ text: String, position: Int) -> (String, NSRange) {
        let nsText = text as NSString
        var start = position
        var end = position
        
        // Ensure position is within bounds
        let safePosition = min(max(0, position), nsText.length)
        
        // Search backwards for paragraph start (double newline or start of text)
        start = safePosition
        while start > 0 {
            let prevChar = nsText.character(at: start - 1)
            if prevChar == 10 { // newline
                if start > 1 && nsText.character(at: start - 2) == 10 {
                    // Found double newline
                    break
                }
            }
            start -= 1
        }
        
        // Search forward for paragraph end (double newline or end of text)
        end = safePosition
        while end < nsText.length {
            let char = nsText.character(at: end)
            if char == 10 { // newline
                if end + 1 < nsText.length && nsText.character(at: end + 1) == 10 {
                    // Found double newline
                    break
                }
            }
            end += 1
        }
        
        let range = NSRange(location: start, length: end - start)
        let paragraph = nsText.substring(with: range)
        
        return (paragraph, range)
    }
    
    // MARK: - Helper Methods for Text Replacement
    
    /// Replace text at a specific range without selection
    private func replaceTextInRange(_ range: NSRange, with newText: String, in element: AXUIElement) throws {
        print("DEBUG: AccessibilityBridge - Replacing text in range: \(range)")
        
        // Get the full text value
        var fullValue: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &fullValue
        )
        
        guard getResult == .success,
              let fullText = fullValue as? String else {
            print("DEBUG: AccessibilityBridge - Failed to get full text value")
            throw AccessibilityError.cannotGetSelection
        }
        
        // Convert to NSString for range operations
        let nsFullText = fullText as NSString
        
        // Ensure range is valid
        guard range.location + range.length <= nsFullText.length else {
            print("DEBUG: AccessibilityBridge - Range out of bounds")
            throw AccessibilityError.unsupportedOperation
        }
        
        // Create the new full text by replacing the range
        let newFullText = nsFullText.replacingCharacters(in: range, with: newText)
        
        // Set the new full text
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newFullText as CFTypeRef
        )
        
        if setResult != .success {
            print("DEBUG: AccessibilityBridge - Failed to set new text value: \(setResult.rawValue)")
            throw AccessibilityError.cannotSetValue
        }
        
        // Calculate the new cursor position (end of the replaced text)
        let newCursorPosition = range.location + newText.count
        
        // Set the cursor position
        var newRange = CFRange(location: newCursorPosition, length: 0)
        if let newAXRange = AXValueCreate(.cfRange, &newRange) {
            let cursorResult = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                newAXRange
            )
            
            if cursorResult == .success {
                print("DEBUG: AccessibilityBridge - Successfully positioned cursor at: \(newCursorPosition)")
            } else {
                print("DEBUG: AccessibilityBridge - Failed to set cursor position: \(cursorResult.rawValue)")
            }
        }
        
        print("DEBUG: AccessibilityBridge - Text replacement completed successfully")
    }
    
    /// Paste text using the system pasteboard
    private func pasteText(_ text: String) {
        print("DEBUG: AccessibilityBridge - Pasting text via pasteboard")
        
        let pasteboard = NSPasteboard.general
        let savedContents = pasteboard.string(forType: .string)
        
        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        simulateKeyCommand(key: CGKeyCode(kVK_ANSI_V), modifiers: [.command])
        
        // Restore original pasteboard contents after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let saved = savedContents {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
    }
    
    
    /// Select all text
    private func selectAll() {
        simulateKeyCommand(key: CGKeyCode(kVK_ANSI_A), modifiers: [.command])
        usleep(50000)
    }
}

extension CGEventFlags {
    static let maskCommand = CGEventFlags.maskCommand
    static let maskAlternate = CGEventFlags.maskAlternate
    static let maskControl = CGEventFlags.maskControl
    static let maskShift = CGEventFlags.maskShift
    
    static let option = CGEventFlags.maskAlternate
    static let command = CGEventFlags.maskCommand
    static let shift = CGEventFlags.maskShift
}