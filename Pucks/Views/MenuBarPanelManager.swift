import SwiftUI
import AppKit
import Combine

// MARK: - PanelPinState

/// Lightweight shared state for panel pin + saved position.
/// Avoids retain cycles between the panel manager and the SwiftUI view.
@MainActor
final class PanelPinState: ObservableObject {
    static let shared = PanelPinState()

    static let didChangeNotification = Notification.Name("com.pucks.panelPinStateChanged")

    @Published var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: "panelIsPinned")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private init() {
        // Default to pinned on first launch
        if UserDefaults.standard.object(forKey: "panelIsPinned") == nil {
            self.isPinned = true
            UserDefaults.standard.set(true, forKey: "panelIsPinned")
        } else {
            self.isPinned = UserDefaults.standard.bool(forKey: "panelIsPinned")
        }
    }
}

// MARK: - MenuBarPanelManager

@MainActor
class MenuBarPanelManager: ObservableObject {

    // MARK: - Properties

    @Published var isPanelVisible: Bool = false

    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var clickOutsideMonitor: Any?
    private var dismissPanelObserver: NSObjectProtocol?
    private var pinStateObserver: NSObjectProtocol?
    private var positionObservers: [NSObjectProtocol] = []

    let panelWidth: CGFloat = 380
    let panelHeight: CGFloat = 160
    let panelExpandedHeight: CGFloat = 480

    // Environment objects to inject into the panel view
    var companionManager: CompanionManager?
    var floatingButtonManager: FloatingSessionButtonManager?
    var selectedTextMonitor: SelectedTextMonitor?

    // Pin state (shared with the SwiftUI view)
    private let pinState = PanelPinState.shared

    // Position persistence keys
    private static let posXKey = "panelPositionX"
    private static let posYKey = "panelPositionY"
    private static let sizeWKey = "panelSizeW"
    private static let sizeHKey = "panelSizeH"

    // MARK: - Notification

    static let dismissPanelNotification = Notification.Name("com.pucks.dismissPanel")
    static let resizePanelNotification = Notification.Name("com.pucks.resizePanel")

    // MARK: - Setup

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = Self.makeMenuBarIcon()
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        setupDismissObserver()
        setupPinStateObserver()

        // If pinned, restore panel automatically on launch
        if pinState.isPinned {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showPanel()
            }
        }
    }

    // MARK: - Status Item Action

    @objc private func statusItemClicked(_ sender: Any?) {
        if isPanelVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Show Panel

    private func showPanel() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        if panel == nil {
            createPanel()
        }

        guard let panel = panel else { return }

        // Determine position: saved (pinned) → near cursor (pinned, no save) → below status item
        let targetFrame: NSRect

        if pinState.isPinned, let savedFrame = loadSavedFrame() {
            targetFrame = savedFrame
        } else if pinState.isPinned {
            // Position near cursor as a sidecar
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main!
            let w = panelWidth
            let h = panelHeight
            var x = mouse.x + 20
            var y = mouse.y - h / 2
            // Keep on screen
            if x + w > screen.visibleFrame.maxX { x = mouse.x - w - 20 }
            y = max(screen.visibleFrame.minY + 4, min(y, screen.visibleFrame.maxY - h - 4))
            x = max(screen.visibleFrame.minX + 4, x)
            targetFrame = NSRect(x: x, y: y, width: w, height: h)
        } else {
            let panelX = buttonFrame.midX - panelWidth / 2
            let panelY = buttonFrame.minY - panelHeight - 4
            targetFrame = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        }

        panel.setFrame(targetFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
        isPanelVisible = true

        if !pinState.isPinned {
            installClickOutsideMonitor()
        }

        installPositionObservers()

        print("[MenuBarPanelManager] Panel shown (pinned: \(pinState.isPinned)).")
    }

    // MARK: - Create Panel

    private func createPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No title bar — using borderless style
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 280, height: 80)
        panel.maxSize = NSSize(width: 420, height: 800)
        panel.contentMinSize = NSSize(width: 280, height: 80)



        // Create the SwiftUI content view
        let rootView = CompanionPanelView()
            .environmentObject(companionManager ?? CompanionManager())
            .environmentObject(floatingButtonManager ?? FloatingSessionButtonManager())
            .environmentObject(selectedTextMonitor ?? SelectedTextMonitor())
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.autoresizingMask = [.width, .height]

        // Wrapper view that clips to rounded corners
        let cornerRadius: CGFloat = 32

        let clipView = NSView(frame: hostingView.frame)
        clipView.autoresizingMask = [.width, .height]
        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = cornerRadius
        clipView.layer?.cornerCurve = .continuous
        clipView.layer?.masksToBounds = true

        let glassView = NSGlassEffectView(frame: hostingView.frame)
        glassView.autoresizingMask = [.width, .height]
        glassView.cornerRadius = cornerRadius
        glassView.style = .regular
        glassView.tintColor = NSColor.black.withAlphaComponent(0.05)
        glassView.contentView = hostingView

        clipView.addSubview(glassView)
        panel.contentView = clipView

        self.panel = panel
    }

    // MARK: - Dismiss Panel

    func dismissPanel() {
        panel?.orderOut(nil)
        isPanelVisible = false
        removeClickOutsideMonitor()
        removePositionObservers()
        print("[MenuBarPanelManager] Panel dismissed.")
    }

    // MARK: - Pin State Observer

    private func setupPinStateObserver() {
        pinStateObserver = NotificationCenter.default.addObserver(
            forName: PanelPinState.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePinStateChanged()
            }
        }
    }

    private func handlePinStateChanged() {
        if pinState.isPinned {
            // Pinned: save current position, remove click-outside dismiss
            removeClickOutsideMonitor()
            saveCurrentPosition()
            print("[MenuBarPanelManager] Panel pinned. Position saved.")
        } else {
            // Unpinned: re-enable click-outside dismiss, clear saved position
            if isPanelVisible {
                installClickOutsideMonitor()
            }
            clearSavedFrame()
            print("[MenuBarPanelManager] Panel unpinned.")
        }
    }

    // MARK: - Position Persistence

    private func installPositionObservers() {
        removePositionObservers()
        guard let panel = panel else { return }

        let moveObs = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pinState.isPinned else { return }
                self.saveCurrentPosition()
            }
        }

        let resizeObs = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pinState.isPinned else { return }
                self.saveCurrentPosition()
            }
        }

        positionObservers = [moveObs, resizeObs]
    }

    private func removePositionObservers() {
        for observer in positionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        positionObservers.removeAll()
    }

    private func saveCurrentPosition() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(Double(frame.origin.x), forKey: Self.posXKey)
        UserDefaults.standard.set(Double(frame.origin.y), forKey: Self.posYKey)
        UserDefaults.standard.set(Double(frame.size.width), forKey: Self.sizeWKey)
        UserDefaults.standard.set(Double(frame.size.height), forKey: Self.sizeHKey)
    }

    private func loadSavedFrame() -> NSRect? {
        let x = UserDefaults.standard.double(forKey: Self.posXKey)
        let y = UserDefaults.standard.double(forKey: Self.posYKey)
        let w = UserDefaults.standard.double(forKey: Self.sizeWKey)
        let h = UserDefaults.standard.double(forKey: Self.sizeHKey)

        // Validate saved frame (must have non-zero size and be on a visible screen)
        guard w >= 340, h >= 460 else { return nil }
        let frame = NSRect(x: x, y: y, width: w, height: h)

        // Verify at least part of the frame is visible on some screen
        let isVisible = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
        return isVisible ? frame : nil
    }

    private func clearSavedFrame() {
        UserDefaults.standard.removeObject(forKey: Self.posXKey)
        UserDefaults.standard.removeObject(forKey: Self.posYKey)
        UserDefaults.standard.removeObject(forKey: Self.sizeWKey)
        UserDefaults.standard.removeObject(forKey: Self.sizeHKey)
    }

    // MARK: - Click Outside Monitor

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self, self.isPanelVisible else { return }
            // Don't dismiss if pinned
            guard !self.pinState.isPinned else { return }

            if let panel = self.panel {
                let clickLocation = NSEvent.mouseLocation
                if !panel.frame.contains(clickLocation) {
                    Task { @MainActor in
                        self.dismissPanel()
                    }
                }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Dismiss Observer

    private var resizePanelObserver: NSObjectProtocol?

    private func setupDismissObserver() {
        dismissPanelObserver = NotificationCenter.default.addObserver(
            forName: Self.dismissPanelNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissPanel()
            }
        }

        resizePanelObserver = NotificationCenter.default.addObserver(
            forName: Self.resizePanelNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleResizeRequest(notification)
            }
        }
    }

    private func handleResizeRequest(_ notification: Notification) {
        guard let panel = panel else { return }
        let targetHeight = (notification.userInfo?["height"] as? CGFloat) ?? panelHeight
        let targetWidth = (notification.userInfo?["width"] as? CGFloat) ?? panel.frame.width

        var frame = panel.frame
        let heightDiff = targetHeight - frame.height
        frame.origin.y -= heightDiff // grow upward
        frame.size.height = targetHeight
        frame.size.width = max(targetWidth, frame.size.width)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Menu Bar Icon

    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = rect.width
            let h = rect.height

            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: w * 0.15, y: h * 0.95))
            arrow.line(to: NSPoint(x: w * 0.15, y: h * 0.13))
            arrow.line(to: NSPoint(x: w * 0.38, y: h * 0.32))
            arrow.line(to: NSPoint(x: w * 0.60, y: h * 0.0))
            arrow.line(to: NSPoint(x: w * 0.72, y: h * 0.12))
            arrow.line(to: NSPoint(x: w * 0.52, y: h * 0.40))
            arrow.line(to: NSPoint(x: w * 0.72, y: h * 0.60))
            arrow.close()

            NSColor.black.setFill()
            arrow.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Cleanup

    deinit {
        let monitor = clickOutsideMonitor
        clickOutsideMonitor = nil
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = dismissPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = resizePanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = pinStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in positionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: - KeyablePanel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}
