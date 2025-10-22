import SwiftUI
import Combine

@main
struct VoiceControlApp: App {
    @StateObject private var commandManager = CommandManager()
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var editManager: EditManager
    @StateObject private var dictationManager: DictationManager
    @StateObject private var dictationHistoryManager: DictationHistoryManager
    @StateObject private var overlayViewModel: OverlayViewModel
    @State private var overlayWindowController: OverlayWindowController?
    @State private var hasSetupApp = false
    @State private var hasShownPermissionDialog = false
    @State private var isCheckingPermissions = false

    init() {
        let audioEngine = AudioEngine()
        let openAIService = OpenAIService()
        let whisperService = WhisperService(openAIService: openAIService)
        let accessibilityBridge = AccessibilityBridge()
        let gptService = GPTService(openAIService: openAIService)

        let commandManager = CommandManager()
        let dictationHistoryManager = DictationHistoryManager()

        let editManager = EditManager(
            audioEngine: audioEngine,
            whisperService: whisperService,
            accessibilityBridge: accessibilityBridge,
            gptService: gptService
        )

        let dictationManager = DictationManager(
            audioEngine: audioEngine,
            whisperService: whisperService,
            accessibilityBridge: accessibilityBridge,
            gptService: gptService
        )
        dictationManager.commandManager = commandManager
        dictationManager.historyManager = dictationHistoryManager
        editManager.commandManager = commandManager

        _commandManager = StateObject(wrappedValue: commandManager)
        _editManager = StateObject(wrappedValue: editManager)
        _dictationManager = StateObject(wrappedValue: dictationManager)
        _dictationHistoryManager = StateObject(wrappedValue: dictationHistoryManager)

        _overlayViewModel = StateObject(wrappedValue: OverlayViewModel(
            commandManager: commandManager,
            editManager: editManager,
            dictationManager: dictationManager
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

                Divider()

                Button("Dictation Mode") {
                    Task { @MainActor in
                        await dictationManager.toggleDictation()
                    }
                }
                .keyboardShortcut("k", modifiers: [.control])

                Button("Edit Mode") {
                    Task { @MainActor in
                        editManager.startEditing()
                    }
                }
                .keyboardShortcut("l", modifiers: [.control])

                Divider()

                Button("Show Home") {
                    openHomeWindow()
                }
                .keyboardShortcut("h", modifiers: [.control])
            }
        }

        #if os(macOS)
        Window("Home", id: "home") {
            DictationHistoryView()
                .environmentObject(dictationHistoryManager)
        }
        .defaultSize(width: 700, height: 500)
        #endif
    }
    
    private func setupApp() {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.setupHUD()
                self.connectComponents()
                self.checkAccessibilityPermission()
                self.setupAppDelegate()
            }
        }
    }
    
    private func setupHUD() {
        overlayWindowController = OverlayWindowController(viewModel: overlayViewModel)
    }
    
    private func connectComponents() {
        commandManager.setHotkeyManager(hotkeyManager)
        
        // Setup edit manager to listen to hotkey events
        editManager.setupHotkeyListener(hotkeyManager: hotkeyManager, commandManager: commandManager)
        
        // Setup dictation manager to listen to hotkey events
        hotkeyManager.dictationHotkeyPressed
            .sink { [weak dictationManager] in
                Task { @MainActor in
                    await dictationManager?.toggleDictation()
                }
            }
            .store(in: &dictationManager.cancellables)
        
        // Setup dictation manager to listen to notification from HUD button
        NotificationCenter.default.publisher(for: .startDictationMode)
            .sink { [weak dictationManager] _ in
                Task { @MainActor in
                    await dictationManager?.toggleDictation()
                }
            }
            .store(in: &dictationManager.cancellables)
        
        // HUD visibility is now handled by OverlayViewModel
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
            DispatchQueue.main.async {
                let hasPermission = HotkeyManager.hasAccessibilityPermission()
                
                if hasPermission {
                    print("🎉 Accessibility permission granted! Reinitializing hotkeys...")
                    self.hotkeyManager.reinitialize()
                    timer.invalidate()
                }
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

        Available hotkeys:
        • Control+J - Voice Commands
        • Control+K - Dictation Mode
        • Control+L - Edit Mode

        Watch the console for debug messages to see if hotkeys are working.
        If you see key events logged, the hotkeys are functioning correctly!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setupAppDelegate() {
        // Create and set custom app delegate to handle dock icon clicks
        let delegate = VoiceControlAppDelegate()
        delegate.openHomeWindow = {
            self.openHomeWindow()
        }
        NSApp.delegate = delegate
    }

    private func openHomeWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Find and bring forward the home window
        for window in NSApp.windows {
            if window.title == "Home" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }

        print("⚠️ Home window not found - may need to be created")
    }
}

// MARK: - App Delegate for Dock Icon Handling

class VoiceControlAppDelegate: NSObject, NSApplicationDelegate {
    var openHomeWindow: (() -> Void)?

    // Called when user clicks dock icon while app is already running
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        print("🖱️ Dock icon clicked - opening home window")
        openHomeWindow?()
        return true
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var hasOpenedHome = false

    var body: some View {
        EmptyView()
            .onAppear {
                if !hasOpenedHome {
                    openWindow(id: "home")
                    hasOpenedHome = true
                }
            }
    }
}

extension View {
    func invisible() -> some View {
        self.frame(width: 0, height: 0)
            .opacity(0)
    }
}