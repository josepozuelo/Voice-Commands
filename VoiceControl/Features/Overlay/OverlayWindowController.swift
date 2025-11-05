import SwiftUI
import AppKit
import Combine

class OverlayWindowController: NSWindowController {
    private var viewModel: OverlayViewModel
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var fixedBottomY: CGFloat = 0
    
    init(viewModel: OverlayViewModel) {
        self.viewModel = viewModel
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
        setupContent()
        observeViewModel()
        setupEscapeKeyMonitor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window as? NSPanel else { return }

        // Configure as non-activating panel
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovable = false
        window.acceptsMouseMovedEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        // Always show the window
        window.orderFrontRegardless()
        positionWindow()

        // Observe window frame changes to maintain fixed bottom
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc private func windowDidResize() {
        maintainFixedBottom()
    }
    
    private func setupContent() {
        guard let window = window else { return }
        
        let contentView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        contentView.layer?.masksToBounds = false
        window.contentView = contentView
    }
    
    private func observeViewModel() {
        viewModel.$state
            .sink { [weak self] state in
                DispatchQueue.main.async {
                    self?.updateWindowSize(for: state)
                    // Don't reposition window after state changes to prevent movement
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateWindowSize(for state: OverlayState) {
        guard let window = window else { return }

        let targetSize: NSSize
        switch state {
        case .collapsed:
            targetSize = NSSize(width: 56, height: 56)
        case .expanded:
            targetSize = NSSize(width: 216, height: 66)
        case .command(let phase):
            switch phase {
            case .classifying:
                targetSize = NSSize(width: 400, height: 100)
            default:
                targetSize = NSSize(width: 350, height: 76)
            }
        case .edit, .dictation:
            targetSize = NSSize(width: 350, height: 76)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            // Keep the left edge and bottom fixed, expand to the right
            let currentLeftX = window.frame.minX

            let newFrame = NSRect(
                x: currentLeftX,
                y: fixedBottomY,
                width: targetSize.width,
                height: targetSize.height
            )
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func maintainFixedBottom() {
        guard let window = window else { return }

        // Re-anchor the bottom if it has drifted
        if window.frame.minY != fixedBottomY {
            let newFrame = NSRect(
                x: window.frame.minX,
                y: fixedBottomY,
                width: window.frame.width,
                height: window.frame.height
            )
            window.setFrame(newFrame, display: true, animate: false)
        }
    }
    
    private func positionWindow() {
        guard let window = window,
              let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let collapsedWidth: CGFloat = 56
        let expandedWidth: CGFloat = 216

        // Position so that when expanded, it will be centered
        // This means the collapsed window's left edge should be offset from center
        let x = screenFrame.midX - expandedWidth / 2
        let y = screenFrame.minY + 40 // 40px from bottom

        window.setFrameOrigin(NSPoint(x: x, y: y))

        // Store the fixed bottom position
        fixedBottomY = y
    }
    
    private func setupEscapeKeyMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                if self?.viewModel.state.isActive == true {
                    self?.viewModel.stop()
                    return nil // Consume the event
                }
            }
            return event
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}