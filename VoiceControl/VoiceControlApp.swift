import SwiftUI
import Combine

@main
struct VoiceControlApp: App {
    @StateObject private var commandManager = CommandManager()
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var editManager: EditManager
    @State private var hudWindowController: CommandHUDWindowController?
    @State private var editModeHUDController: EditModeHUDWindowController?
    @State private var hasSetupApp = false
    @State private var hasShownPermissionDialog = false
    @State private var isCheckingPermissions = false
    
    init() {
        let audioEngine = AudioEngine()
        let openAIService = OpenAIService()
        let whisperService = WhisperService(openAIService: openAIService)
        let accessibilityBridge = AccessibilityBridge()
        let gptService = GPTService(openAIService: openAIService)
        
        _editManager = StateObject(wrappedValue: EditManager(
            audioEngine: audioEngine,
            whisperService: whisperService,
            accessibilityBridge: accessibilityBridge,
            gptService: gptService
        ))
    }
    
    var body: some Scene {
        WindowGroup(content: {
            ContentView()
                .frame(width: 0, height: 0)
                .invisible()
                .onAppear {
                    if !hasSetupApp {
                        hasSetupApp = true
                        setupApp()
                    }
                }
        })
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About VoiceControl") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check Permissions") {
                    checkPermissionsManually()
                }
                .keyboardShortcut("p", modifiers: [.command])
                
                Button("Test Hotkeys") {
                    testHotkeysManually()
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
    }
    
    private func setupApp() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupHUD()
                self.connectComponents()
                self.checkAccessibilityPermission()
            }
        }
    }
    
    private func setupHUD() {
        hudWindowController = CommandHUDWindowController(commandManager: commandManager)
        editModeHUDController = EditModeHUDWindowController(editManager: editManager)
    }
    
    private func connectComponents() {
        commandManager.setHotkeyManager(hotkeyManager)
        
        // Setup edit manager to listen to hotkey events
        editManager.setupHotkeyListener(hotkeyManager: hotkeyManager)
    }
    
    private func checkAccessibilityPermission() {
        guard !isCheckingPermissions else {
            print("🔄 Already checking permissions, skipping...")
            return
        }
        
        isCheckingPermissions = true
        
        print("🔍 Checking accessibility permission...")
        let hasPermission = HotkeyManager.hasAccessibilityPermission()
        
        if hasPermission {
            print("✅ Accessibility permission granted - setting up hotkeys")
            hotkeyManager.reinitialize()
        } else if !hasShownPermissionDialog {
            print("📋 Accessibility permission missing - showing custom dialog")
            // Only show our custom dialog - don't call AXIsProcessTrustedWithOptions here
            // as it can cause confusing double prompts
            showAccessibilityPermissionAlert()
        } else {
            print("ℹ️  Permission dialog already shown, starting background monitoring")
            startPermissionMonitoring()
        }
        
        isCheckingPermissions = false
    }
    
    private func showAccessibilityPermissionAlert() {
        hasShownPermissionDialog = true
        
        let alert = NSAlert()
        alert.messageText = "VoiceControl Needs Accessibility Access"
        alert.informativeText = """
        VoiceControl requires Accessibility permission to detect global hotkeys like Control+Shift+V.
        
        Please:
        1. Click "Open System Settings" below
        2. Navigate to Privacy & Security → Accessibility
        3. Enable VoiceControl in the list
        4. The app will automatically detect when permission is granted
        
        Without this permission, you can only use the button in the menu bar.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Skip for Now")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            print("🚀 Opening System Settings for Accessibility permission")
            // Open System Settings directly without triggering system permission dialog
            openSystemSettings()
            
            // Start monitoring for permission changes
            startPermissionMonitoring()
        } else {
            print("⏭️  User skipped permission setup")
            // Even if user skips, start monitoring in case they grant permission later
            startPermissionMonitoring()
        }
    }
    
    private func openSystemSettings() {
        // Try multiple methods to open Accessibility settings
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:"
        ]
        
        for urlString in urls {
            if let url = URL(string: urlString) {
                if NSWorkspace.shared.open(url) {
                    print("✅ Opened System Settings with URL: \(urlString)")
                    return
                }
            }
        }
        print("❌ Failed to open System Settings")
    }
    
    private func startPermissionMonitoring() {
        print("👀 Starting permission monitoring...")
        
        // Check every 2 seconds for permission changes
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            let hasPermission = HotkeyManager.hasAccessibilityPermission()
            
            if hasPermission {
                print("🎉 Accessibility permission granted! Reinitializing hotkeys...")
                DispatchQueue.main.async {
                    self.hotkeyManager.reinitialize()
                }
                timer.invalidate()
            }
        }
    }
    
    private func checkPermissionsManually() {
        print("🔄 Manual permission check requested")
        hasShownPermissionDialog = false // Reset dialog state
        isCheckingPermissions = false // Reset checking state
        checkAccessibilityPermission()
    }
    
    private func testHotkeysManually() {
        print("🧪 Manual hotkey test requested")
        hotkeyManager.reinitialize()
        
        let alert = NSAlert()
        alert.messageText = "Hotkey Test"
        alert.informativeText = """
        Testing hotkeys now...
        
        Please try pressing Control+Shift+V.
        
        Watch the console for debug messages to see if hotkeys are working.
        If you see key events logged, the hotkeys are functioning correctly!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct ContentView: View {
    var body: some View {
        EmptyView()
    }
}

extension View {
    func invisible() -> some View {
        self.frame(width: 0, height: 0)
            .opacity(0)
    }
}