import SwiftUI
import AppKit
import AVFoundation
import Speech
import Carbon
import UniformTypeIdentifiers

// MARK: - Panel Tab

enum PanelTab: String, CaseIterable, Identifiable {
    case chat = "Chat"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - CompanionPanelView

struct CompanionPanelView: View {

    @EnvironmentObject var floatingButtonManager: FloatingSessionButtonManager
    @EnvironmentObject var companionManager: CompanionManager
    @EnvironmentObject var selectedTextMonitor: SelectedTextMonitor

    // MARK: - State

    @State private var selectedTab: PanelTab = .chat
    @State private var isCapturingShortcut: Bool = false
    @State private var shortcutEventMonitor: Any?
    @State private var screenPermissionPollTask: Task<Void, Never>?
    @State private var showDebugSelectedText: Bool = UserDefaults.standard.bool(forKey: "showDebugSelectedText")
    @State private var isMainWindowCurrentlyFocused: Bool = true

    // Permission states
    @State private var hasMicrophonePermission: Bool = false
    @State private var hasScreenRecordingPermission: Bool = false
    @State private var hasAccessibilityPermission: Bool = false
    @State private var hasSpeechRecognitionPermission: Bool = false

    @StateObject private var shortcutConfig = PushToTalkShortcutConfiguration.shared
    @StateObject private var cursorConfig = CursorAppearanceConfiguration.shared
    @ObservedObject private var pinState = PanelPinState.shared

    // Onboarding
    @State private var hasCompletedOnboarding: Bool = false
    @State private var welcomeText: String = ""
    @State private var showWelcome: Bool = false

    // MARK: - Constants

    private let fullWelcomeText = "You're all set. Hit Start to meet Pucks."
    private let privacyNote = "Nothing runs in the background. Pucks only takes a screenshot when you press the hotkey."
    private let messageMaxWidth: CGFloat = 260
    private let surfaceCornerRadius: CGFloat = 12
    private let accentColor = Color(red: 0.34, green: 0.63, blue: 0.98)

    // MARK: - Computed

    private var allPermissionsGranted: Bool {
        hasMicrophonePermission && hasScreenRecordingPermission && hasAccessibilityPermission && hasSpeechRecognitionPermission
    }

    // MARK: - Body

    @State private var isCompact: Bool = false

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                if !isCompact {
                    panelHeader
                }

                if !hasCompletedOnboarding {
                    onboardingView
                        .onAppear { requestPanelResize(height: 520) }
                } else if isCompact && selectedTab == .chat && allPermissionsGranted {
                    chatTabView
                } else {
                    chatTabView
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                hasCompletedOnboarding = true
            }
            checkAllPermissions()
            configureFloatingButtonManager()
            startObservingMainWindowFocusChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkAllPermissions()
        }
        .onChange(of: companionManager.voiceState) { _, newState in
            switch newState {
            case .listening, .thinking, .speaking:
                requestPanelResize(height: 480)
            case .idle:
                // Shrink back after a delay so user can read the response
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if companionManager.voiceState == .idle {
                        requestPanelResize(height: 160)
                    }
                }
            }
        }
        .onDisappear {
            stopShortcutCapture()
            screenPermissionPollTask?.cancel()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Panel Header
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var panelHeader: some View {
        HStack(spacing: 6) {
            // Status chip
            HStack(spacing: 5) {
                Circle()
                    .fill(voiceStateColor)
                    .frame(width: 7, height: 7)
                Text(voiceStateLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(.white.opacity(0.04)), in: .capsule)

            Spacer()

            // Settings
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Pin
            Button {
                pinState.isPinned.toggle()
            } label: {
                Image(systemName: pinState.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(pinState.isPinned ? accentColor : .white.opacity(0.45))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pinState.isPinned ? "Unpin panel" : "Pin panel open")

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit Pucks")
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(WindowDragArea())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat Tab
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Threshold height below which we switch to compact horizontal layout
    private let compactHeightThreshold: CGFloat = 220

    @State private var isDragOver = false

    private var chatTabView: some View {
        GeometryReader { geo in
            if geo.size.height < compactHeightThreshold {
                compactChatLayout
                    .onAppear { isCompact = true }
                    .onChange(of: geo.size.height) { _, h in
                        isCompact = h < compactHeightThreshold
                    }
            } else {
                fullChatLayout
                    .onAppear { isCompact = false }
                    .onChange(of: geo.size.height) { _, h in
                        isCompact = h < compactHeightThreshold
                    }
            }
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 24))
                            Text("Drop image")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(accentColor)
                    }
                    .padding(8)
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let nsImage = image as? NSImage else { return }
                    Task { @MainActor in
                        companionManager.attachDroppedImage(nsImage)
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let nsImage = NSImage(contentsOf: url) else { return }
                    Task { @MainActor in
                        companionManager.attachDroppedImage(nsImage)
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: Full (tall) chat layout

    private var fullChatLayout: some View {
        VStack(spacing: 0) {
            // Inline permission warning
            if !allPermissionsGranted {
                permissionsWarningBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            // Selected text card
            if selectedTextMonitor.hasSelection {
                selectedTextCard
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }

            // Debug selected text
            if showDebugSelectedText && selectedTextMonitor.hasSelection {
                debugSelectedTextView
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Conversation area (expands to fill available space)
            conversationSection
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .frame(maxHeight: .infinity)

            // Thinking indicator
            if companionManager.voiceState == .thinking {
                thinkingIndicator
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Active transcript
            if !companionManager.activeTurnTranscriptText.isEmpty {
                activeTranscriptView
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // ── Bottom pinned area ──

            // Attached screenshots
            if !companionManager.attachedScreenshots.isEmpty {
                attachedScreenshotsRow
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // Microphone controls
            microphoneSection
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 10)

            // Screenshot intercept — subtle bottom strip
            if companionManager.screenshotInterceptor.pendingScreenshot != nil {
                screenshotInterceptCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: Compact (short/wide) chat layout

    private var compactChatLayout: some View {
        HStack(spacing: 10) {
            // Conversation / transcript — left side
            VStack(alignment: .leading, spacing: 4) {
                // Status + shortcut row
                HStack(spacing: 6) {
                    Circle()
                        .fill(voiceStateColor)
                        .frame(width: 6, height: 6)
                    Text(voiceStateLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text(shortcutConfig.label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                // Content
                if companionManager.voiceState == .thinking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("Thinking\u{2026}")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else if !companionManager.activeTurnTranscriptText.isEmpty {
                    Text(companionManager.activeTurnTranscriptText)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .italic()
                        .lineLimit(3)
                } else if let lastTurn = companionManager.conversationHistory.last {
                    Text(lastTurn.assistantResponse)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(3)
                        .textSelection(.enabled)
                } else {
                    Text("Hold \(shortcutConfig.label) and speak")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.vertical, 8)

            // Mic button — right side
            Button(action: toggleRecording) {
                Image(systemName: micIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle()
                            .fill(micButtonColor)
                    }
                    .glassEffect(.regular.tint(micButtonColor.opacity(0.3)), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: micButtonColor.opacity(0.35), radius: 6, y: 2)
            .opacity(!allPermissionsGranted ? 0.6 : 1.0)
            .padding(.trailing, 12)
        }
        .background(WindowDragArea())
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat: Permissions Warning
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var permissionsWarningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)

            Text("Missing permissions")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Button {
                SettingsWindowController.shared.show(tab: .permissions)
            } label: {
                Text("Fix")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(10)
        .glassEffect(.regular.tint(.orange.opacity(0.06)), in: .rect(cornerRadius: 10))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat: Selected Text
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var selectedTextCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.cursor")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))

            Text(selectedTextPreview)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(2)

            Spacer(minLength: 4)

            Button("Suggest") {
                companionManager.suggestForSelectedText()
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(companionManager.voiceState == .thinking || companionManager.voiceState == .listening)
        }
        .padding(10)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 10))
    }

    private var debugSelectedTextView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 9))
                Text("Debug: Raw Selected Text")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.orange.opacity(0.7))

            Text(selectedTextMonitor.selectedText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(10)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .glassEffect(.regular.tint(.orange.opacity(0.04)), in: .rect(cornerRadius: 8))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat: Conversation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var conversationSection: some View {
        VStack(spacing: 0) {
            // Clear button
            if !companionManager.conversationHistory.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        companionManager.clearConversation()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                            Text("Clear")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if companionManager.conversationHistory.isEmpty {
                            emptyConversationPlaceholder
                        } else {
                            ForEach(companionManager.conversationHistory) { turn in
                            VStack(spacing: 6) {
                                // User message — right aligned
                                HStack {
                                    Spacer(minLength: 48)
                                    messageBubble(turn.userTranscript, isUser: true)
                                }

                                // Assistant response — left aligned
                                HStack {
                                    messageBubble(turn.assistantResponse, isUser: false)
                                    Spacer(minLength: 48)
                                }
                            }
                            .id(turn.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
                .scrollIndicators(.hidden)
                .onChange(of: companionManager.conversationHistory.count) {
                    if let last = companionManager.conversationHistory.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyConversationPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.15))

            Text("Hold \(shortcutConfig.label) and speak,\nor tap the button below.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func messageBubble(_ text: String, isUser: Bool) -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            Text(isUser ? "You" : "Pucks")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(
                    .regular.tint(isUser ? accentColor.opacity(0.14) : .white.opacity(0.05)),
                    in: .rect(cornerRadius: 12)
                )
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat: Active Transcript + Thinking
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var activeTranscriptView: some View {
        HStack {
            Spacer()
            Text(companionManager.activeTurnTranscriptText)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .italic()
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: messageMaxWidth, alignment: .trailing)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 10))
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("Thinking…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(10)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 10))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat: Screenshot Intercept
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var screenshotInterceptCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))

            Text("Screenshot copied")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            Button {
                companionManager.attachPendingScreenshot()
            } label: {
                Text("Attach")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)

            Button {
                companionManager.screenshotInterceptor.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var attachedScreenshotsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(companionManager.attachedScreenshots) { screenshot in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: screenshot.thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )

                        Button {
                            companionManager.removeAttachedScreenshot(screenshot.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }

                Text("\(companionManager.attachedScreenshots.count) attached")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Chat: Microphone Controls
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var microphoneSection: some View {
        VStack(spacing: 6) {
            Button(action: toggleRecording) {
                Image(systemName: micIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background {
                        Circle()
                            .fill(micButtonColor)
                    }
                    .glassEffect(.regular.tint(micButtonColor.opacity(0.3)), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: micButtonColor.opacity(0.4), radius: 8, y: 2)
            .opacity(!allPermissionsGranted ? 0.6 : 1.0)

            Text(micCaption)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var micIcon: String {
        switch companionManager.voiceState {
        case .listening: return "stop.fill"
        case .thinking: return "stop.fill"
        case .speaking: return "stop.fill"
        case .idle: return "mic.fill"
        }
    }

    private var micButtonColor: Color {
        switch companionManager.voiceState {
        case .listening: return .red
        case .thinking: return .orange
        case .speaking: return .green
        case .idle: return accentColor
        }
    }

    private var micCaption: String {
        if !allPermissionsGranted { return "Grant permissions first" }
        switch companionManager.voiceState {
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .idle: return ""
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(granted ? .green : .white.opacity(0.4))
                .frame(width: 20)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            } else {
                Button("Grant") { action() }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(
            .regular.tint(granted ? .green.opacity(0.1) : .white.opacity(0.04)),
            in: .rect(cornerRadius: 8)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Computed Properties
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var voiceStateColor: Color {
        switch companionManager.voiceState {
        case .idle: return .white.opacity(0.4)
        case .listening: return accentColor
        case .thinking: return .orange
        case .speaking: return .green
        }
    }

    private var voiceStateLabel: String {
        switch companionManager.voiceState {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }

    private var selectedTextPreview: String {
        let normalized = selectedTextMonitor.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count > 140 { return "\"\(normalized.prefix(137))…\"" }
        return "\"\(normalized)\""
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Onboarding
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var onboardingView: some View {
        VStack(spacing: 20) {
            if showWelcome {
                welcomeSection
            } else {
                onboardingPermissionsSection
            }
        }
        .padding(24)
    }

    private var onboardingPermissionsSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 36))
                .foregroundColor(accentColor)

            Text("Pucks needs a few permissions")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 8) {
                permissionRow(title: "Microphone", icon: "mic.fill",
                              granted: hasMicrophonePermission, action: requestMicrophonePermission)
                permissionRow(title: "Screen Recording", icon: "rectangle.dashed.badge.record",
                              granted: hasScreenRecordingPermission, action: requestScreenRecordingPermission)
                permissionRow(title: "Accessibility", icon: "accessibility",
                              granted: hasAccessibilityPermission, action: requestAccessibilityPermission)
                permissionRow(title: "Speech Recognition", icon: "waveform",
                              granted: hasSpeechRecognitionPermission, action: requestSpeechRecognitionPermission)
            }

            Text(privacyNote)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            if allPermissionsGranted {
                Button {
                    withAnimation { showWelcome = true }
                    animateWelcomeText()
                } label: {
                    Text("Continue")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .transition(.opacity)
            }
        }
    }

    private var welcomeSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 40))
                .foregroundColor(accentColor)

            Text(welcomeText)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Button {
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            } label: {
                Text("Start")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Actions
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func toggleRecording() {
        checkAllPermissions()
        guard allPermissionsGranted else {
            SettingsWindowController.shared.show(tab: .permissions)
            return
        }

        switch companionManager.voiceState {
        case .listening:
            companionManager.isRecordingFromMicrophoneButton = false
            companionManager.stopSession()
        case .thinking, .speaking:
            companionManager.cancelCurrentResponse()
        case .idle:
            companionManager.isRecordingFromMicrophoneButton = true
            Task { try? await companionManager.startSession() }
        }
    }

    private func animateWelcomeText() {
        welcomeText = ""
        var charIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            if charIndex < fullWelcomeText.count {
                let idx = fullWelcomeText.index(fullWelcomeText.startIndex, offsetBy: charIndex)
                welcomeText.append(fullWelcomeText[idx])
                charIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Permission Checks
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func checkAllPermissions() {
        hasMicrophonePermission = CompanionPermissionCenter.hasMicrophonePermission()
        hasAccessibilityPermission = CompanionPermissionCenter.hasAccessibilityPermission()
        hasSpeechRecognitionPermission = CompanionPermissionCenter.hasSpeechRecognitionPermission()
        Task {
            let granted = await CompanionPermissionCenter.hasScreenRecordingPermissionAsync()
            await MainActor.run {
                hasScreenRecordingPermission = granted
                // Auto-complete onboarding if all permissions are already granted
                if allPermissionsGranted && !hasCompletedOnboarding {
                    hasCompletedOnboarding = true
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                }
            }
        }
    }

    private func requestMicrophonePermission() {
        CompanionPermissionCenter.requestMicrophonePermission { granted in
            hasMicrophonePermission = granted
        }
    }

    private func requestScreenRecordingPermission() {
        CompanionPermissionCenter.requestScreenRecordingPermission()
        screenPermissionPollTask?.cancel()
        screenPermissionPollTask = Task {
            for _ in 0..<12 {
                let granted = await CompanionPermissionCenter.hasScreenRecordingPermissionAsync()
                await MainActor.run { hasScreenRecordingPermission = granted }
                if granted { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func requestAccessibilityPermission() {
        hasAccessibilityPermission = CompanionPermissionCenter.requestAccessibilityPermission()
    }

    private func requestSpeechRecognitionPermission() {
        CompanionPermissionCenter.requestSpeechRecognitionPermission { granted in
            hasSpeechRecognitionPermission = granted
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shortcut Capture
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func startShortcutCapture() {
        stopShortcutCapture()
        isCapturingShortcut = true

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isCapturingShortcut else { return event }
            let modifiers = PushToTalkShortcutConfiguration.captureModifiers(from: event.modifierFlags)
            let disallowed: Set<UInt16> = [UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option), UInt16(kVK_Control)]
            guard !disallowed.contains(event.keyCode), modifiers != 0 else { return nil }
            shortcutConfig.update(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopShortcutCapture()
            return nil
        }
    }

    private func stopShortcutCapture() {
        isCapturingShortcut = false
        if let m = shortcutEventMonitor {
            NSEvent.removeMonitor(m)
            shortcutEventMonitor = nil
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Floating Button & Window Focus
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func configureFloatingButtonManager() {
        floatingButtonManager.onFloatingButtonClicked = {
            bringMainWindowToFront()
        }
    }

    private func startObservingMainWindowFocusChanges() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window == NSApplication.shared.mainWindow else { return }
            isMainWindowCurrentlyFocused = true
            updateFloatingButtonVisibility()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  window == NSApplication.shared.mainWindow else { return }
            isMainWindowCurrentlyFocused = false
            updateFloatingButtonVisibility()
        }
    }

    private func updateFloatingButtonVisibility() {
        if !companionManager.conversationHistory.isEmpty && !isMainWindowCurrentlyFocused {
            floatingButtonManager.showFloatingButton()
        } else {
            floatingButtonManager.hideFloatingButton()
        }
    }

    private func requestPanelResize(width: CGFloat? = nil, height: CGFloat) {
        var info: [String: CGFloat] = ["height": height]
        if let w = width { info["width"] = w }
        NotificationCenter.default.post(
            name: MenuBarPanelManager.resizePanelNotification,
            object: nil,
            userInfo: info
        )
    }

    private func bringMainWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.mainWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.mainWindow?.orderFrontRegardless()
    }
}

// MARK: - WindowDragArea

/// An NSViewRepresentable that makes its area draggable for window movement,
/// even when the panel has isMovableByWindowBackground = false.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
