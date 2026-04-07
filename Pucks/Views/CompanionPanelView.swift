import SwiftUI
import AppKit
import AVFoundation
import Speech
import Carbon

// MARK: - CompanionPanelView

struct CompanionPanelView: View {

    @EnvironmentObject var floatingButtonManager: FloatingSessionButtonManager
    @EnvironmentObject var companionManager: CompanionManager
    @EnvironmentObject var selectedTextMonitor: SelectedTextMonitor

    // MARK: - State

    @State private var isMainWindowCurrentlyFocused: Bool = true
    @State private var showWelcome: Bool = false
    @State private var showOnboardingVideo: Bool = false
    @State private var showOnboardingPrompt: Bool = false
    @State private var onboardingPromptText: String = ""
    @State private var onboardingPromptOpacity: Double = 0.0
    @State private var welcomeText: String = ""
    @State private var isShowingSettings: Bool = false
    @State private var isCapturingShortcut: Bool = false
    @State private var shortcutEventMonitor: Any?
    @State private var screenPermissionPollTask: Task<Void, Never>?

    // Permission states
    @State private var hasMicrophonePermission: Bool = false
    @State private var hasScreenRecordingPermission: Bool = false
    @State private var hasAccessibilityPermission: Bool = false
    @State private var hasSpeechRecognitionPermission: Bool = false
    @StateObject private var shortcutConfig = PushToTalkShortcutConfiguration.shared
    @StateObject private var cursorConfig = CursorAppearanceConfiguration.shared

    // Onboarding
    @State private var hasCompletedOnboarding: Bool = false
    @State private var isSessionRunning: Bool = false

    // MARK: - Constants

    private let fullWelcomeText = "You're all set. Hit Start to meet Pucks."
    private let privacyNote = "Nothing runs in the background. Pucks will only take a screenshot when you press the hot key. So, you can give that permission in peace. If you are still sus, eh, I can't do much there champ."
    private let muxHLSURL = "https://stream.mux.com/e5jB8UuSrtFABVnTHCR7k3sIsmcUHCyhtLu1tzqLlfs.m3u8"
    private let messageMaxWidth: CGFloat = 248
    private let surfaceCornerRadius: CGFloat = 14
    private let accentColor = Color(red: 0.34, green: 0.63, blue: 0.98)

    // MARK: - Computed

    private var allPermissionsGranted: Bool {
        hasMicrophonePermission && hasScreenRecordingPermission && hasAccessibilityPermission && hasSpeechRecognitionPermission
    }

    private var somePermissionsRevoked: Bool {
        hasCompletedOnboarding && !allPermissionsGranted
    }

    private var missingRequiredPermissions: Bool {
        !allPermissionsGranted
    }

    // MARK: - Body

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            ZStack {
                Color.white.opacity(0.015)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    dragHeaderView

                    if !hasCompletedOnboarding {
                        onboardingView
                    } else {
                        mainSessionView
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            checkAllPermissions()
            configureFloatingButtonManager()
            startObservingMainWindowFocusChanges()

            if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                hasCompletedOnboarding = true
            }
        }
        .onDisappear {
            stopShortcutCapture()
            screenPermissionPollTask?.cancel()
        }
    }

    // MARK: - Onboarding View

    private var onboardingView: some View {
        VStack(spacing: 20) {
            if showOnboardingVideo {
                onboardingVideoSection
            } else if showWelcome {
                welcomeSection
            } else {
                permissionsSection
            }
        }
        .padding(24)
    }

    private var onboardingVideoSection: some View {
        VStack(spacing: 16) {
            OnboardingVideoPlayerView(
                hlsURL: muxHLSURL,
                onVideoEnded: {
                    skipOnboardingVideo()
                }
            )
            .frame(width: onboardingVideoPlayerWidth, height: onboardingVideoPlayerHeight)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

            Text("Meet Pucks")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))

            Button(action: { skipOnboardingVideo() }) {
                Text("Skip")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }

    private func skipOnboardingVideo() {
        withAnimation(.easeInOut(duration: 0.5)) {
            showOnboardingVideo = false
            showWelcome = true
        }
        animateWelcomeText()
    }

    private var welcomeSection: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 44))
                .foregroundColor(.blue)

            Text(welcomeText)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .animation(.easeIn, value: welcomeText)

            Text(privacyNote)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Button(action: {
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }) {
                Text("Start")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .tint(allPermissionsGranted ? .blue : .gray)
            .disabled(!allPermissionsGranted)
        }
    }

    private var permissionsSection: some View {
        VStack(spacing: 20) {
            Text("Pucks needs a few permissions")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            VStack(spacing: 12) {
                permissionRow(
                    title: "Microphone",
                    icon: "mic.fill",
                    granted: hasMicrophonePermission,
                    action: requestMicrophonePermission
                )
                permissionRow(
                    title: "Screen Recording",
                    icon: "rectangle.dashed.badge.record",
                    granted: hasScreenRecordingPermission,
                    action: requestScreenRecordingPermission
                )
                permissionRow(
                    title: "Accessibility",
                    icon: "accessibility",
                    granted: hasAccessibilityPermission,
                    action: requestAccessibilityPermission
                )
                permissionRow(
                    title: "Speech Recognition",
                    icon: "waveform",
                    granted: hasSpeechRecognitionPermission,
                    action: requestSpeechRecognitionPermission
                )
            }

            Text(privacyNote)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Text("Screen Recording is granted to the currently running build. If macOS does not show the dialog, use the Grant button to open the correct Settings pane for this build.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if allPermissionsGranted {
                Button(action: {
                    // Skip video, go straight to welcome/start
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showWelcome = true
                    }
                    animateWelcomeText()
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Main Session View

    private var mainSessionView: some View {
        VStack(spacing: 0) {
            sessionHeader
                .padding(.top, 12)

            if missingRequiredPermissions {
                mainPermissionsCard
            }

            if selectedTextMonitor.hasSelection {
                selectedTextCard
            }

            conversationSection
                .frame(maxHeight: .infinity)

            if companionManager.voiceState == .thinking {
                thinkingIndicator
            }

            if isShowingSettings {
                utilitySectionHeader
                shortcutSettingsView
                cursorSettingsView
            }

            microphoneSection
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var dragHeaderView: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 5)

            Text("Drag here. Resize from any edge or corner.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.55))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var sessionHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pucks")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                voiceStateBadge

                Button {
                    isShowingSettings.toggle()
                } label: {
                    Image(systemName: isShowingSettings ? "xmark.circle.fill" : "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var voiceStateBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(voiceStateColor)
                .frame(width: 8, height: 8)

            Text(voiceStateLabel)
                .font(.caption)
                .foregroundColor(.white.opacity(0.78))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.white.opacity(0.06)), in: .capsule)
    }

    private var selectedTextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Selected Text", systemImage: "text.cursor")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Button("Suggest Rewrite") {
                    companionManager.suggestForSelectedText()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(companionManager.voiceState == .thinking || companionManager.voiceState == .listening)
            }

            Text(selectedTextPreview)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.045)), in: .rect(cornerRadius: surfaceCornerRadius))
        .padding(.top, 8)
    }

    private var mainPermissionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)

                Text("Permissions Required")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Button {
                    checkAllPermissions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.glass)
            }

            Text("Pucks cannot record until the missing permissions below are granted.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.55))

            VStack(spacing: 8) {
                if !hasMicrophonePermission {
                    permissionRow(
                        title: "Microphone",
                        icon: "mic.fill",
                        granted: false,
                        action: requestMicrophonePermission
                    )
                }

                if !hasScreenRecordingPermission {
                    permissionRow(
                        title: "Screen Recording",
                        icon: "rectangle.dashed.badge.record",
                        granted: false,
                        action: requestScreenRecordingPermission
                    )
                }

                if !hasAccessibilityPermission {
                    permissionRow(
                        title: "Accessibility",
                        icon: "accessibility",
                        granted: false,
                        action: requestAccessibilityPermission
                    )
                }

                if !hasSpeechRecognitionPermission {
                    permissionRow(
                        title: "Speech Recognition",
                        icon: "waveform",
                        granted: false,
                        action: requestSpeechRecognitionPermission
                    )
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.045)), in: .rect(cornerRadius: surfaceCornerRadius))
        .padding(.top, 8)
    }

    private var voiceStateColor: Color {
        switch companionManager.voiceState {
        case .idle: return .white.opacity(0.45)
        case .listening: return accentColor
        case .thinking: return .white.opacity(0.7)
        case .speaking: return .white.opacity(0.7)
        }
    }

    private var voiceStateLabel: String {
        switch companionManager.voiceState {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.82))

            conversationHistoryView
                .frame(maxHeight: .infinity)

            if !companionManager.activeTurnTranscriptText.isEmpty {
                activeTranscriptView
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: surfaceCornerRadius))
        .padding(.top, 8)
    }

    private var conversationHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if companionManager.conversationHistory.isEmpty {
                        Text("Start a session and the conversation will appear here.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } else {
                        ForEach(companionManager.conversationHistory) { turn in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Spacer(minLength: 56)
                                    messageBubble(
                                        turn.userTranscript,
                                        roleLabel: "You",
                                        tint: accentColor.opacity(0.18),
                                        alignment: .trailing
                                    )
                                }

                                HStack {
                                    messageBubble(
                                        turn.assistantResponse,
                                        roleLabel: "Pucks",
                                        tint: .white.opacity(0.05),
                                        alignment: .leading
                                    )
                                    Spacer(minLength: 56)
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
                if let lastTurn = companionManager.conversationHistory.last {
                    withAnimation {
                        proxy.scrollTo(lastTurn.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(primaryActionTitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))

                Spacer()

                if !missingRequiredPermissions {
                    Text(shortcutConfig.label)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white.opacity(0.58))
                }
            }

            Button(action: {
                toggleRecording()
            }) {
                Label(
                    companionManager.voiceState == .listening ? "Stop Listening" : "Start Listening",
                    systemImage: companionManager.voiceState == .listening ? "stop.fill" : "mic.fill"
                )
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.glassProminent)
            .tint(accentColor)
            .disabled(companionManager.voiceState == .thinking)
            .opacity(companionManager.voiceState == .thinking ? 0.5 : 1.0)

            Text(primaryActionCaption)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(12)
        .glassEffect(.regular.tint(accentColor.opacity(0.08)), in: .rect(cornerRadius: surfaceCornerRadius))
        .padding(.top, 10)
    }

    private var activeTranscriptView: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Live Transcript")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(companionManager.activeTurnTranscriptText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.72))
                .italic()
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 10))
        }
    }

    private var utilitySectionHeader: some View {
        HStack {
            Text("Utilities")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .padding(.top, 10)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            BlueCursorSpinnerView()
                .frame(width: 18, height: 18)
            Text("Thinking…")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.white.opacity(0.035)), in: .rect(cornerRadius: 12))
        .padding(.top, 8)
    }

    private var shortcutSettingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Push-to-Talk")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                Spacer()
                Text(shortcutConfig.label)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.58))
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if isCapturingShortcut {
                        stopShortcutCapture()
                    } else {
                        startShortcutCapture()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCapturingShortcut ? "keyboard.badge.ellipsis" : "keyboard")
                        Text(isCapturingShortcut ? "Press shortcut..." : shortcutConfig.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.glass)
                .tint(isCapturingShortcut ? accentColor : .white)

                Button("Reset Default") {
                    shortcutConfig.resetToDefault()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            Text("Click the shortcut field, then press the combo you want. Changes apply immediately.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.035)), in: .rect(cornerRadius: surfaceCornerRadius))
        .padding(.top, 8)
    }

    private var cursorSettingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cursor")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(CursorStyle.allCases) { style in
                    Button {
                        cursorConfig.style = style
                    } label: {
                        VStack(spacing: 6) {
                            cursorStyleIcon(style)
                                .frame(width: 18, height: 18)
                            Text(style.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.82))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(
                            .regular.tint(
                                cursorConfig.style == style
                                    ? .blue.opacity(0.48)
                                    : .white.opacity(0.08)
                            ),
                            in: .rect(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.glass)
                }
            }

            HStack {
                Text("Scale")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Text(cursorConfig.scale, format: .number.precision(.fractionLength(2)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
            }

            Slider(value: $cursorConfig.scale, in: 0.6...2.0, step: 0.05)
                .tint(accentColor)
        }
        .padding(12)
        .glassEffect(.regular.tint(.white.opacity(0.035)), in: .rect(cornerRadius: surfaceCornerRadius))
        .padding(.top, 8)
    }

    @ViewBuilder
    private func cursorStyleIcon(_ style: CursorStyle) -> some View {
        switch style {
        case .arrow:
            Image(systemName: "arrow.up.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        case .dot:
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
        case .target:
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        case .ring:
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 14, height: 14)
        case .diamond:
            Image(systemName: "diamond.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Permission Row

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(granted ? .green : .white.opacity(0.5))
                .frame(width: 24)

            Text(title)
                .font(.body)
                .foregroundColor(.white)

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.glass)
                .tint(accentColor)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(
            .regular.tint(granted ? .white.opacity(0.03) : .white.opacity(0.035)),
            in: .rect(cornerRadius: 8)
        )
    }

    private func messageBubble(
        _ text: String,
        roleLabel: String,
        tint: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(roleLabel)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))

            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: messageMaxWidth, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Recording Toggle

    private func toggleRecording() {
        checkAllPermissions()

        guard allPermissionsGranted else {
            isShowingSettings = false
            return
        }

        if companionManager.voiceState == .listening {
            companionManager.isRecordingFromMicrophoneButton = false
            companionManager.stopSession()
        } else if companionManager.voiceState == .idle || companionManager.voiceState == .speaking {
            companionManager.isRecordingFromMicrophoneButton = true
            Task {
                try? await companionManager.startSession()
            }
            isSessionRunning = true
        }
    }

    private var selectedTextPreview: String {
        let normalized = selectedTextMonitor.selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count > 220 {
            return "\"\(normalized.prefix(217))...\""
        }

        return "\"\(normalized)\""
    }

    private var headerSubtitle: String {
        switch companionManager.voiceState {
        case .idle:
            return missingRequiredPermissions ? "Finish permissions to start a voice session." : "Ready for a voice session."
        case .listening:
            return "Pucks is listening."
        case .thinking:
            return "Pucks is working on a response."
        case .speaking:
            return "Pucks is speaking."
        }
    }

    private var primaryActionTitle: String {
        switch companionManager.voiceState {
        case .listening:
            return "Session Live"
        case .thinking:
            return "Processing"
        case .speaking:
            return "Replying"
        case .idle:
            return "Voice Session"
        }
    }

    private var primaryActionCaption: String {
        if missingRequiredPermissions {
            return "Grant the required permissions above before starting."
        }

        switch companionManager.voiceState {
        case .listening:
            return "Tap to stop, or release the push-to-talk shortcut."
        case .thinking:
            return "A response is being prepared."
        case .speaking:
            return "Tap to start a new turn when ready."
        case .idle:
            return "Use the button or hold the push-to-talk shortcut."
        }
    }

    // MARK: - Welcome Text Animation

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

    // MARK: - Permission Checks

    private func checkAllPermissions() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
        checkSpeechRecognitionPermission()
        Task {
            await checkScreenRecordingPermission()
        }
    }

    private func checkMicrophonePermission() {
        hasMicrophonePermission = CompanionPermissionCenter.hasMicrophonePermission()
    }

    private func checkScreenRecordingPermission() async {
        let granted = await CompanionPermissionCenter.hasScreenRecordingPermissionAsync()
        await MainActor.run {
            hasScreenRecordingPermission = granted
        }
    }

    private func checkAccessibilityPermission() {
        hasAccessibilityPermission = CompanionPermissionCenter.hasAccessibilityPermission()
    }

    private func checkSpeechRecognitionPermission() {
        hasSpeechRecognitionPermission = CompanionPermissionCenter.hasSpeechRecognitionPermission()
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
                await MainActor.run {
                    hasScreenRecordingPermission = granted
                }
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

    // MARK: - Floating Button Manager

    func configureFloatingButtonManager() {
        floatingButtonManager.onFloatingButtonClicked = { [self] in
            bringMainWindowToFront()
        }
    }

    private func startShortcutCapture() {
        stopShortcutCapture()
        isCapturingShortcut = true

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isCapturingShortcut else { return event }

            let modifiers = PushToTalkShortcutConfiguration.captureModifiers(from: event.modifierFlags)
            let disallowedKeyCodes: Set<UInt16> = [UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option), UInt16(kVK_Control)]

            guard !disallowedKeyCodes.contains(event.keyCode), modifiers != 0 else {
                return nil
            }

            shortcutConfig.update(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopShortcutCapture()
            return nil
        }
    }

    private func stopShortcutCapture() {
        isCapturingShortcut = false
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
            self.shortcutEventMonitor = nil
        }
    }

    // MARK: - Window Focus Observation

    func startObservingMainWindowFocusChanges() {
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

    // MARK: - Floating Button Visibility

    func updateFloatingButtonVisibility() {
        if isSessionRunning && !isMainWindowCurrentlyFocused {
            floatingButtonManager.showFloatingButton()
        } else {
            floatingButtonManager.hideFloatingButton()
        }
    }

    // MARK: - Bring Window to Front

    func bringMainWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.mainWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.mainWindow?.orderFrontRegardless()
    }
}

// MARK: - BlueCursorSpinnerView

struct BlueCursorSpinnerView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Triangle()
            .fill(Color.blue)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.0)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Video Player Dimensions

let onboardingVideoPlayerWidth: CGFloat = 320
let onboardingVideoPlayerHeight: CGFloat = 180
