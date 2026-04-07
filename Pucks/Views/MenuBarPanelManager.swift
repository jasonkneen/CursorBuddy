import SwiftUI
import AppKit
import Combine

// MARK: - MenuBarPanelManager

@MainActor
class MenuBarPanelManager: ObservableObject {

    // MARK: - Properties

    @Published var isPanelVisible: Bool = false

    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var clickOutsideMonitor: Any?
    private var dismissPanelObserver: NSObjectProtocol?

    let panelWidth: CGFloat = 380
    let panelHeight: CGFloat = 560

    // Environment objects to inject into the panel view
    var companionManager: CompanionManager?
    var floatingButtonManager: FloatingSessionButtonManager?
    var selectedTextMonitor: SelectedTextMonitor?

    // MARK: - Notification

    static let dismissPanelNotification = Notification.Name("com.pucks.dismissPanel")

    // MARK: - Setup

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = Self.makeMenuBarIcon()
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true  // adapts to light/dark menu bar
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        setupDismissObserver()
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

        // Position panel below the status item, centered
        let panelX = buttonFrame.midX - panelWidth / 2
        let panelY = buttonFrame.minY - panelHeight - 4

        panel.setFrame(
            NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            display: true
        )

        panel.makeKeyAndOrderFront(nil)
        isPanelVisible = true

        installClickOutsideMonitor()

        print("[MenuBarPanelManager] Panel shown.")
    }

    // MARK: - Create Panel

    private func createPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 340, height: 460)
        panel.contentMinSize = NSSize(width: 340, height: 460)

        // Create the SwiftUI content view
        let rootView = CompanionPanelView()
            .environmentObject(companionManager ?? CompanionManager())
            .environmentObject(floatingButtonManager ?? FloatingSessionButtonManager())
            .environmentObject(selectedTextMonitor ?? SelectedTextMonitor())
        let hostingView = NSHostingView(rootView: rootView)

        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentView = hostingView

        self.panel = panel
    }

    // MARK: - Dismiss Panel

    func dismissPanel() {
        panel?.orderOut(nil)
        isPanelVisible = false
        removeClickOutsideMonitor()
        print("[MenuBarPanelManager] Panel dismissed.")
    }

    // MARK: - Click Outside Monitor

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self, self.isPanelVisible else { return }

            // Check if click is outside the panel
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

    // MARK: - Menu Bar Icon

    /// Draws a tiny cursor-pointer icon for the menu bar
    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = rect.width
            let h = rect.height

            // Pointer arrow — tip at top-left, scaled to 18x18
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: w * 0.15, y: h * 0.95))   // tip (top-left in flipped=false means top)
            arrow.line(to: NSPoint(x: w * 0.15, y: h * 0.13))   // down left edge
            arrow.line(to: NSPoint(x: w * 0.38, y: h * 0.32))   // notch left
            arrow.line(to: NSPoint(x: w * 0.60, y: h * 0.0))    // tail bottom
            arrow.line(to: NSPoint(x: w * 0.72, y: h * 0.12))   // tail right
            arrow.line(to: NSPoint(x: w * 0.52, y: h * 0.40))   // notch right
            arrow.line(to: NSPoint(x: w * 0.72, y: h * 0.60))   // wing tip
            arrow.close()

            NSColor.black.setFill()
            arrow.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

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
    }
}

// MARK: - KeyablePanel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}
