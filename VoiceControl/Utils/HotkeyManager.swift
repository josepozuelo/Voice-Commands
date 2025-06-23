import Foundation
import AppKit
import Combine
import ApplicationServices

class HotkeyManager: ObservableObject {
    var commandHotkeyPressed = PassthroughSubject<Void, Never>()
    var dictationHotkeyPressed = PassthroughSubject<Void, Never>()
    var editHotkeyPressed = PassthroughSubject<Void, Never>()
    
    private var globalMonitor: Any?
    
    private func logToFile(_ message: String) {
        let logPath = "/tmp/voicecontrol_debug.log"
        let timestamp = Date().description
        let logMessage = "\(timestamp): \(message)\n"
        
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }
    
    init() {
        print("🚀 HotkeyManager: Initializing with NSEvent global monitor...")
        logToFile("🚀 HotkeyManager: Initializing with NSEvent global monitor...")
        setupGlobalMonitor()
        print("🚀 HotkeyManager: Initialization complete")
        logToFile("🚀 HotkeyManager: Initialization complete")
    }
    
    deinit {
        cleanup()
    }
    
    func reinitialize() {
        print("🔄 HotkeyManager: Reinitializing...")
        cleanup()
        setupGlobalMonitor()
    }
    
    private func setupGlobalMonitor() {
        print("🔧 HotkeyManager: Setting up NSEvent global monitor...")
        logToFile("🔧 HotkeyManager: Setting up NSEvent global monitor...")
        
        // Check if we have accessibility permission using the CORRECT API
        let isTrusted = AXIsProcessTrusted()
        logToFile("📊 AXIsProcessTrusted returned: \(isTrusted)")
        
        if isTrusted {
            print("✅ Accessibility permission granted - setting up global monitor")
            logToFile("✅ Accessibility permission granted - setting up global monitor")
            installGlobalMonitor()
        } else {
            print("❌ Accessibility permission not granted")
            logToFile("❌ Accessibility permission not granted")
            // Don't set up monitor without permission - it won't work
        }
    }
    
    private func installGlobalMonitor() {
        print("📍 Installing NSEvent global monitor...")
        logToFile("📍 Installing NSEvent global monitor...")
        
        // Use the modern, recommended NSEvent API for global monitoring
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        if globalMonitor != nil {
            print("✅ Global key monitor installed successfully")
            logToFile("✅ Global key monitor installed successfully")
            print("🎯 Listening for Control+Shift+V...")
            logToFile("🎯 Listening for Control+Shift+V (keyCode 9)...")
            print("   Monitor object: \(String(describing: globalMonitor))")
        } else {
            print("❌ Failed to install global key monitor")
            logToFile("❌ Failed to install global key monitor")
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        // Extract modifier states
        let hasControl = modifiers.contains(.control)
        let hasShift = modifiers.contains(.shift)
        let hasCommand = modifiers.contains(.command)
        let hasOption = modifiers.contains(.option)
        
        // Debug logging for our target keys
        if (hasControl && hasShift) || (hasCommand && hasOption) {
            print("⌨️  Key Event - Code: \(keyCode), Modifiers: [Control:\(hasControl) Shift:\(hasShift) Cmd:\(hasCommand) Opt:\(hasOption)]")
        }
        
        // Check for Control+Shift+V (keyCode 9 is V)
        if keyCode == 9 && hasControl && hasShift {
            print("🚀 Control+Shift+V detected! Triggering voice command...")
            logToFile("🚀 Control+Shift+V detected! Triggering voice command...")
            DispatchQueue.main.async {
                self.commandHotkeyPressed.send()
            }
        }
        // Check for Option+Command+D (keyCode 2 is D)
        else if keyCode == 2 && hasCommand && hasOption {
            print("🎤 Option+Command+D detected! Triggering dictation...")
            DispatchQueue.main.async {
                self.dictationHotkeyPressed.send()
            }
        }
        // Check for Option+Command+E (keyCode 14 is E)
        else if keyCode == 14 && hasCommand && hasOption {
            print("✏️  Option+Command+E detected! Triggering edit mode...")
            DispatchQueue.main.async {
                self.editHotkeyPressed.send()
            }
        }
    }
    
    private func cleanup() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        print("🧹 HotkeyManager cleanup complete")
    }
    
    // MARK: - Accessibility Permission Methods
    
    static func hasAccessibilityPermission() -> Bool {
        // Use the CORRECT API - AXIsProcessTrusted is the recommended way!
        return AXIsProcessTrusted()
    }
    
}