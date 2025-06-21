import Foundation
import ApplicationServices
import Carbon

class AccessibilityBridge {
    enum AccessibilityError: LocalizedError {
        case noAccessibilityPermission
        case failedToGetFocusedElement
        case failedToPerformAction
        case unsupportedOperation
        
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
            }
        }
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
        case .lastWord, .previousWord:
            simulateKeyCommand(key: CGKeyCode(kVK_LeftArrow), modifiers: [.option, .shift])
        case .sentence:
            try selectSentence()
        case .lastSentence, .previousSentence:
            try selectPreviousSentence()
        case .paragraph:
            try selectParagraph()
        case .lastParagraph, .previousParagraph:
            try selectPreviousParagraph()
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
        default:
            throw AccessibilityError.unsupportedOperation
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
    
    private func selectParagraph() throws {
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
        
        Thread.sleep(forTimeInterval: 0.01)
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