import SwiftUI

@main
struct PucksApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // Pure menu bar app — no windows from SwiftUI.
        // All UI is driven by MenuBarPanelManager (NSStatusItem + NSPanel).
        Settings {
            EmptyView()
        }
    }
}
