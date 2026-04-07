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
        ZStack {
            Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
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
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
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
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(allPermissionsGranted
                                ? Color.blue
                                : Color.gray.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
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
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Main Session View

    private var mainSessionView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                voiceStateIndicator
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                Button {
                    isShowingSettings.toggle()
                } label: {
                    Image(systemName: isShowingSettings ? "xmark.circle.fill" : "gearshape.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)

            if missingRequiredPermissions {
                mainPermissionsCard
            }

            if selectedTextMonitor.hasSelection {
                selectedTextCard
            }

            // Conversation history
            conversationHistoryView
                .frame(maxHeight: .infinity)

            // Active transcript
            if !companionManager.activeTurnTranscriptText.isEmpty {
                activeTranscriptView
            }

            // Thinking indicator
            if companionManager.voiceState == .thinking {
                HStack(spacing: 8) {
                    BlueCursorSpinnerView()
                        .frame(width: 18, height: 18)
                    Text("Thinking...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.vertical, 8)
            }

            if isShowingSettings {
                shortcutSettingsView
                cursorSettingsView
            }

            // Microphone button
            microphoneButton
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
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
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var voiceStateIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(voiceStateColor)
                .frame(width: 8, height: 8)

            Text(voiceStateLabel)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Spacer()
        }
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
                .buttonStyle(.borderedProminent)
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
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
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                )
        )
        .padding(.top, 8)
    }

    private var voiceStateColor: Color {
        switch companionManager.voiceState {
        case .idle: return .gray
        case .listening: return .red
        case .thinking: return .blue
        case .speaking: return .green
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

    private var conversationHistoryView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(companionManager.conversationHistory) { turn in
                        VStack(alignment: .leading, spacing: 6) {
                            // User message
                            HStack {
                                Spacer()
                                Text(turn.userTranscript)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.blue.opacity(0.3))
                                    )
                            }

                            // Assistant message
                            HStack {
                                Text(turn.assistantResponse)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.08))
                                    )
                                Spacer()
                            }
                        }
                        .id(turn.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: companionManager.conversationHistory.count) {
                if let lastTurn = companionManager.conversationHistory.last {
                    withAnimation {
                        proxy.scrollTo(lastTurn.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var activeTranscriptView: some View {
        HStack {
            Spacer()
            Text(companionManager.activeTurnTranscriptText)
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .italic()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )
        }
        .padding(.vertical, 4)
    }

    private var microphoneButton: some View {
        Button(action: {
            toggleRecording()
        }) {
            ZStack {
                Circle()
                    .fill(
                        companionManager.voiceState == .listening
                            ? Color.red
                            : Color.blue
                    )
                    .frame(width: 48, height: 48)
                    .shadow(
                        color: (companionManager.voiceState == .listening ? Color.red : Color.blue).opacity(0.4),
                        radius: 7,
                        y: 2
                    )

                Image(systemName: companionManager.voiceState == .listening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(companionManager.voiceState == .thinking)
        .opacity(companionManager.voiceState == .thinking ? 0.5 : 1.0)
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
                    .foregroundColor(.blue)
            }

            HStack(spacing: 10) {
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
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isCapturingShortcut ? Color.blue.opacity(0.9) : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button("Reset Default") {
                    shortcutConfig.resetToDefault()
                }
                .buttonStyle(.bordered)
            }

            Text("Click the shortcut field, then press the combo you want. Changes apply immediately.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.top, 8)
    }

    private var cursorSettingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cursor")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.75))

            HStack(spacing: 10) {
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
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    cursorConfig.style == style
                                        ? Color.blue.opacity(0.9)
                                        : Color.white.opacity(0.06)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    cursorConfig.style == style
                                        ? Color.blue.opacity(0.95)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Scale")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Text(cursorConfig.scale, format: .number.precision(.fractionLength(2)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
            }

            Slider(value: $cursorConfig.scale, in: 0.6...2.0, step: 0.05)
                .tint(.blue)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
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
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.15))
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
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
