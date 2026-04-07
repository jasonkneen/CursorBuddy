import AppKit
import SwiftUI
import Combine

/// Manages window positioning relative to the screen, status bar, and cursor location.
@MainActor
final class WindowPositionManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isCursorOnThisScreen: Bool = true
    @Published private(set) var screenSize: CGSize = .zero

    // MARK: - Private

    private var cursorTrackingTimer: Timer?
    private weak var trackedScreen: NSScreen?

    // MARK: - Lifecycle

    init() {
        updateScreenSize()
        startCursorTracking()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateScreenSize()
            }
        }
    }

    deinit {
        cursorTrackingTimer?.invalidate()
    }

    // MARK: - Public API

    /// Returns the frame to position a panel near the given status item button.
    func panelFrame(
        forPanelSize panelSize: CGSize,
        nearStatusItem statusItemFrame: NSRect,
        on screen: NSScreen
    ) -> NSRect {
        let screenFrame = screen.visibleFrame

        // Center horizontally under the status item
        var x = statusItemFrame.midX - panelSize.width / 2

        // Keep on screen
        x = max(screenFrame.minX + 4, min(x, screenFrame.maxX - panelSize.width - 4))

        // Place just below the menu bar
        let y = screenFrame.maxY - panelSize.height

        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    /// Returns the frame to position a panel centered at the top of the given screen.
    func panelFrame(
        forPanelSize panelSize: CGSize,
        centeredTopOf screen: NSScreen
    ) -> NSRect {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height
        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    /// Returns the frame to position a panel at the bottom-right of the given screen.
    func panelFrame(
        forPanelSize panelSize: CGSize,
        bottomRightOf screen: NSScreen,
        padding: CGFloat = 16
    ) -> NSRect {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - panelSize.width - padding
        let y = screenFrame.minY + padding
        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    /// Returns the frame to position a panel near the current cursor location.
    func panelFrame(
        forPanelSize panelSize: CGSize,
        nearCursor offset: CGPoint = CGPoint(x: 20, y: -20)
    ) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation

        guard let screen = screenContainingCursor() else {
            return NSRect(origin: mouseLocation, size: panelSize)
        }

        let screenFrame = screen.visibleFrame

        var x = mouseLocation.x + offset.x
        var y = mouseLocation.y + offset.y - panelSize.height

        // Keep on screen
        if x + panelSize.width > screenFrame.maxX {
            x = mouseLocation.x - panelSize.width - abs(offset.x)
        }
        if y < screenFrame.minY {
            y = screenFrame.minY
        }
        if x < screenFrame.minX {
            x = screenFrame.minX
        }

        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    /// Returns the screen that currently contains the cursor.
    func screenContainingCursor() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    /// Applies a frame to a panel, animating if desired.
    func position(_ panel: NSPanel, frame: NSRect, animate: Bool = false) {
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: - Private

    private func updateScreenSize() {
        if let screen = NSScreen.main {
            screenSize = screen.visibleFrame.size
        }
    }

    private func startCursorTracking() {
        cursorTrackingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCursorScreen()
            }
        }
    }

    private func updateCursorScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }

        if let tracked = trackedScreen {
            isCursorOnThisScreen = (cursorScreen == tracked)
        } else {
            isCursorOnThisScreen = true
        }
    }

    /// Set which screen this manager should track the cursor against.
    func trackScreen(_ screen: NSScreen) {
        trackedScreen = screen
        updateCursorScreen()
    }
}
