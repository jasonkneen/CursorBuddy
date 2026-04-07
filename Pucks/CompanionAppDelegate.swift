import Cocoa
import SwiftUI
import ServiceManagement
import PostHog
import Foundation

@MainActor
class CompanionAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    // MARK: - Properties

    @Published var companionManager: CompanionManager?
    var menuBarPanelManager: MenuBarPanelManager?
    var floatingSessionButtonManager: FloatingSessionButtonManager?

    // Push-to-talk
    private var shortcutMonitor: GlobalPushToTalkShortcutMonitor?
    private var pttOverlayManager: GlobalPushToTalkOverlayManager?
    private var shortcutChangedObserver: NSObjectProtocol?

    // Cursor overlay
    var elementDetector: ElementLocationDetector?
    var selectedTextMonitor: SelectedTextMonitor?
    private var overlayWindowManager: OverlayWindowManager?
    private var voiceStateObservable: VoiceStateObservable?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPostHog()
        registerAsLoginItem()
        initializeManagers()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    deinit {
        if let shortcutChangedObserver {
            NotificationCenter.default.removeObserver(shortcutChangedObserver)
        }
    }

    // MARK: - Setup

    private func setupPostHog() {
        let posthogApiKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? ""
        guard !posthogApiKey.isEmpty else {
            print("[Pucks] PostHog API key not configured, skipping analytics setup.")
            return
        }
        let config = PostHogConfig(apiKey: posthogApiKey, host: "https://app.posthog.com")
        PostHogSDK.shared.setup(config)
        print("[Pucks] PostHog analytics initialized.")
    }

    private func registerAsLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("[Pucks] Registered as login item.")
            } catch {
                print("[Pucks] Failed to register as login item: \(error)")
            }
        }
    }

    private func initializeManagers() {
        Task { @MainActor in
            // 1. Core companion manager
            let manager: CompanionManager = CompanionManager()
            self.companionManager = manager

            // 2. Element location detector (cursor overlay)
            let detector = ElementLocationDetector()
            self.elementDetector = detector
            let selectedTextMonitor = SelectedTextMonitor()
            self.selectedTextMonitor = selectedTextMonitor
            // Wire up the element detector to the companion manager
            manager.elementDetector = detector
            manager.selectedTextMonitor = selectedTextMonitor

            // 3. Floating session button
            let floatingManager = FloatingSessionButtonManager()
            self.floatingSessionButtonManager = floatingManager
            manager.screenCapture.floatingButtonWindowToExcludeFromCaptures = floatingManager.floatingButtonPanel

            // 4. Menu bar status item
            let menuBar = MenuBarPanelManager()
            menuBar.companionManager = manager
            menuBar.floatingButtonManager = floatingManager
            menuBar.selectedTextMonitor = selectedTextMonitor
            menuBar.setupStatusItem()
            self.menuBarPanelManager = menuBar

            // 5. Overlay windows (for cursor animation)
            let overlayMgr = OverlayWindowManager.shared
            self.overlayWindowManager = overlayMgr
            let vsObs = VoiceStateObservable()
            self.voiceStateObservable = vsObs
            manager.voiceStateObservable = vsObs
            setupCursorOverlay(
                detector: detector,
                selectedTextMonitor: selectedTextMonitor,
                overlayManager: overlayMgr,
                voiceState: vsObs
            )

            // 6. Push-to-talk shortcut monitor
            observeShortcutChanges()
            setupPushToTalk(companionManager: manager)

            // 7. PTT visual overlay
            let pttOverlay = GlobalPushToTalkOverlayManager()
            self.pttOverlayManager = pttOverlay
            manager.pttOverlayManager = pttOverlay

            APIKeyConfig.printStatus()
            print("[Pucks] All managers initialized. Push-to-talk ready (hold \(PushToTalkShortcutConfiguration.shared.label)).")
            print("[Pucks] Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "??")")
        }
    }

    // MARK: - Cursor Overlay

    @MainActor private func setupCursorOverlay(
        detector: ElementLocationDetector,
        selectedTextMonitor: SelectedTextMonitor,
        overlayManager: OverlayWindowManager,
        voiceState: VoiceStateObservable
    ) {
        overlayManager.setContent {
            CursorOverlayView(
                detector: detector,
                voiceState: voiceState,
                selectedTextMonitor: selectedTextMonitor
            )
        }
        overlayManager.overlayMode = .idle
        print("[Pucks] Cursor overlay initialized on \(NSScreen.screens.count) screen(s).")
    }

    // MARK: - Push-to-Talk

    @MainActor private func observeShortcutChanges() {
        guard shortcutChangedObserver == nil else { return }

        shortcutChangedObserver = NotificationCenter.default.addObserver(
            forName: PushToTalkShortcutConfiguration.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let companionManager = self.companionManager else { return }
                self.setupPushToTalk(companionManager: companionManager)
            }
        }
    }

    @MainActor private func setupPushToTalk(companionManager: CompanionManager) {
        shortcutMonitor?.stop()

        let monitor = GlobalPushToTalkShortcutMonitor()
        let shortcutConfig = PushToTalkShortcutConfiguration.shared
        monitor.keyCode = shortcutConfig.keyCode
        monitor.modifiers = shortcutConfig.modifiers

        monitor.onShortcutPressed = { [weak companionManager] in
            // Callbacks come from the run loop thread — dispatch to MainActor
            Task { @MainActor in
                guard let manager = companionManager else { return }
                print("[Pucks] Push-to-talk: shortcut PRESSED")
                manager.isRecordingFromKeyboardShortcut = true
                // PTT overlay disabled — cursor chip shows state instead
                do {
                    try await manager.startSession()
                } catch {
                    print("[Pucks] Push-to-talk start error: \(error)")
                }
            }
        }

        monitor.onShortcutReleased = { [weak companionManager] in
            Task { @MainActor in
                guard let manager = companionManager else { return }
                print("[Pucks] Push-to-talk: shortcut RELEASED")
                // PTT overlay disabled — cursor chip shows state instead
                manager.isRecordingFromKeyboardShortcut = false
                manager.stopSession()
            }
        }

        let started = monitor.start()
        self.shortcutMonitor = monitor

        if started {
            print("[Pucks] Global push-to-talk hotkey active (\(shortcutConfig.label)).")
        } else {
            print("[Pucks] Push-to-talk failed to start.")
        }
    }
}
