import AppKit
import SwiftUI

// MARK: - OverlayWindow

/// A transparent, click-through NSPanel used to render cursor animations
/// and other overlay content on top of all other windows.
class OverlayWindow: NSPanel {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Transparent, non-interactive overlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true

        // Float above normal windows
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Keep it alive
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    /// Convenience initializer that covers a given screen frame.
    convenience init(for screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    // Never become key or main – we're purely visual.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Overlay Mode

enum OverlayMode: Equatable {
    case hidden
    case idle
    case listening
    case processing
    case responding
    case navigating
}

// MARK: - OverlayWindowManager

/// Creates and manages one overlay window per connected screen.
@MainActor
final class OverlayWindowManager: ObservableObject {

    static let shared = OverlayWindowManager()

    @Published var overlayMode: OverlayMode = .hidden {
        didSet { applyVisibility() }
    }

    @Published private(set) var isOverlayVisible: Bool = false

    /// One overlay window per screen, keyed by screen's unique id.
    private var windows: [CGDirectDisplayID: OverlayWindow] = [:]

    private init() {
        rebuildWindows()
        observeScreenChanges()
    }

    // MARK: - Public

    /// Returns the overlay window covering the given screen (if any).
    func window(for screen: NSScreen) -> OverlayWindow? {
        guard let displayID = screen.displayID else { return nil }
        return windows[displayID]
    }

    /// Returns all currently-managed overlay windows.
    var allWindows: [OverlayWindow] {
        Array(windows.values)
    }

    /// Sets SwiftUI content on every overlay window.
    func setContent<V: View>(@ViewBuilder _ content: () -> V) {
        let view = content()
        for window in windows.values {
            window.contentView = NSHostingView(rootView: view)
        }
    }

    // MARK: - Private

    private func applyVisibility() {
        let shouldShow = overlayMode != .hidden
        isOverlayVisible = shouldShow

        for window in windows.values {
            if shouldShow {
                window.orderFrontRegardless()
            } else {
                window.orderOut(nil)
            }
        }
    }

    private func rebuildWindows() {
        // Tear down old windows
        for window in windows.values {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()

        // Create one overlay per screen
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let overlay = OverlayWindow(for: screen)
            windows[displayID] = overlay
        }

        applyVisibility()
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindows()
            }
        }
    }
}

// MARK: - NSScreen helper

extension NSScreen {
    /// The CGDirectDisplayID for this screen.
    var displayID: CGDirectDisplayID? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return id
    }
}
