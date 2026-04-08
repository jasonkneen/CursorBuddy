import SwiftUI
import AppKit
import Carbon

// MARK: - Settings Window Controller

@MainActor
final class SettingsWindowController: NSObject, @unchecked Sendable {
    static let shared = SettingsWindowController()

    private let settingsWindow: NSWindow

    private override init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Pucks Settings"
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .popUpMenu
        win.appearance = NSAppearance(named: .darkAqua)
        self.settingsWindow = win
        super.init()
        win.delegate = nil  // prevent retain cycle

        // Set content synchronously so window isn't empty on first show
        let manager = CompanionAppDelegate.shared.companionManager ?? CompanionManager()
        let settingsView = SettingsView()
            .environmentObject(manager)
        let hosting = NSHostingView(rootView: settingsView)
        win.contentView = hosting
    }

    /// Which tab to select on next show. Read by SettingsView via shared state.
    static var pendingTab: SettingsTab?

    /// Drop window level to normal so system dialogs appear above, then restore after 2s.
    func temporarilyLowerLevel() {
        settingsWindow.level = .normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.settingsWindow.level = .popUpMenu
        }
    }

    func show(tab: SettingsTab? = nil) {
        if let tab {
            Self.pendingTab = tab
            NotificationCenter.default.post(name: .settingsTabChanged, object: tab)
        }
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let settingsTabChanged = Notification.Name("settingsTabChanged")
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case apiKeys = "API Keys"
    case transcription = "Transcription"
    case tts = "Text-to-Speech"
    case shortcuts = "Shortcuts"
    case appearance = "Appearance"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .apiKeys: return "key.fill"
        case .transcription: return "waveform"
        case .tts: return "speaker.wave.2.fill"
        case .shortcuts: return "keyboard"
        case .appearance: return "paintbrush"
        case .permissions: return "lock.shield"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .apiKeys

    private func onTabNotification(_ notification: Notification) {
        if let tab = notification.object as? SettingsTab {
            selectedTab = tab
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13))
                                .frame(width: 16)
                            Text(tab.rawValue)
                                .font(.system(size: 13))
                            Spacer()
                        }
                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.12))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(width: 160)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))

            Divider()

            // Content
            TabContentView(selectedTab: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .settingsTabChanged)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
    }
}

// MARK: - Tab Content

struct TabContentView: View {
    let selectedTab: SettingsTab

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch selectedTab {
                case .apiKeys:
                    APIKeysSettingsView()
                case .transcription:
                    TranscriptionSettingsView()
                case .tts:
                    TTSSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .permissions:
                    PermissionsSettingsView()
                }
            }
            .padding(20)
        }
    }
}

// MARK: - API Keys Settings

struct APIKeysSettingsView: View {
    @State private var anthropicKey: String = APIKeysManager.shared.anthropicKey ?? ""
    @State private var openAIKey: String = APIKeysManager.shared.openAIKey ?? ""
    @State private var elevenLabsKey: String = APIKeysManager.shared.elevenLabsKey ?? ""
    @State private var cartesiaKey: String = APIKeysManager.shared.cartesiaKey ?? ""
    @State private var deepgramKey: String = APIKeysManager.shared.deepgramKey ?? ""
    @State private var assemblyAIKey: String = APIKeysManager.shared.assemblyAIKey ?? ""

    @State private var showSaveAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Keys")
                .font(.system(size: 18, weight: .semibold))

            Text("Keys are stored in ~/.pucks/keys.json. For production, use environment variables.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 12) {
                keyRow(title: "Anthropic", subtitle: "Claude models (claude-sonnet-4-6, etc.)", key: $anthropicKey)
                keyRow(title: "OpenAI", subtitle: "Whisper transcription, Codex", key: $openAIKey)
                keyRow(title: "ElevenLabs", subtitle: "Text-to-speech voice", key: $elevenLabsKey)
                keyRow(title: "Cartesia", subtitle: "Real-time voice synthesis (Sonic)", key: $cartesiaKey)
                keyRow(title: "Deepgram", subtitle: "Streaming speech-to-text with VAD", key: $deepgramKey)
                keyRow(title: "AssemblyAI", subtitle: "Streaming speech-to-text", key: $assemblyAIKey)
            }

            HStack {
                Spacer()
                Button("Save Keys") {
                    saveKeys()
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func keyRow(title: String, subtitle: String, key: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text("— \(subtitle)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            SecureField("sk-...", text: key)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.06))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    private func saveKeys() {
        APIKeysManager.shared.save(
            anthropicKey: anthropicKey.isEmpty ? nil : anthropicKey,
            openAIKey: openAIKey.isEmpty ? nil : openAIKey,
            elevenLabsKey: elevenLabsKey.isEmpty ? nil : elevenLabsKey,
            cartesiaKey: cartesiaKey.isEmpty ? nil : cartesiaKey,
            deepgramKey: deepgramKey.isEmpty ? nil : deepgramKey,
            assemblyAIKey: assemblyAIKey.isEmpty ? nil : assemblyAIKey
        )
        showSaveAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveAlert = false
        }
    }
}

// MARK: - Transcription Settings

struct TranscriptionSettingsView: View {
    @State private var selectedProvider: TranscriptionProviderType = TranscriptionProviderType.current
    @State private var enableVAD: Bool = UserDefaults.standard.bool(forKey: "vadEnabled")
    @State private var vadThreshold: Double = {
        let val = UserDefaults.standard.double(forKey: "vadThreshold")
        return val == 0 ? 0.03 : val
    }()
    @State private var vadSilenceMs: Int = {
        let val = UserDefaults.standard.integer(forKey: "vadSilenceMs")
        return val == 0 ? 800 : val
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription")
                .font(.system(size: 18, weight: .semibold))

            Text("Choose how your voice is transcribed to text.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))

            Divider()

            // Provider selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.system(size: 13, weight: .medium))

                ForEach(TranscriptionProviderType.allCases) { provider in
                    Button {
                        selectedProvider = provider
                        selectedProvider.save()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(provider.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                            if selectedProvider == provider {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedProvider == provider ? Color.blue.opacity(0.12) : .white.opacity(0.04))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedProvider == provider ? Color.blue.opacity(0.3) : .clear, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // VAD Settings
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $enableVAD) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice Activity Detection")
                            .font(.system(size: 13, weight: .medium))
                        Text("Automatically stop recording when you stop speaking")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .toggleStyle(.switch)
                .tint(.blue)
                .onChange(of: enableVAD) { _, val in
                    UserDefaults.standard.set(val, forKey: "vadEnabled")
                }

                if enableVAD {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Silence threshold")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.2f", vadThreshold))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: $vadThreshold, in: 0.01...0.3, step: 0.01)
                            .tint(.blue)
                            .onChange(of: vadThreshold) { _, val in
                                UserDefaults.standard.set(val, forKey: "vadThreshold")
                            }

                        HStack {
                            Text("Silence duration to trigger stop")
                                .font(.system(size: 12))
                            Spacer()
                            Text("\(vadSilenceMs)ms")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        Slider(value: Binding(
                            get: { Double(vadSilenceMs) },
                            set: {
                                vadSilenceMs = Int($0)
                                UserDefaults.standard.set(vadSilenceMs, forKey: "vadSilenceMs")
                            }
                        ), in: 300...3000, step: 100)
                        .tint(.blue)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.03))
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TTS Settings

struct TTSSettingsView: View {
    @State private var selectedTTS: TTSProviderType = TTSProviderType.current
    @State private var selectedVoice: String = UserDefaults.standard.string(forKey: "ttsVoiceId") ?? "21m00Tcm4TlvDq8ikWAM"
    @State private var cartesiaVoiceId: String = UserDefaults.standard.string(forKey: "cartesiaVoiceId") ?? ""
    @State private var ttsSpeed: Double = {
        let val = UserDefaults.standard.double(forKey: "ttsSpeed")
        return val == 0 ? 1.0 : val
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Text-to-Speech")
                .font(.system(size: 18, weight: .semibold))

            Text("Pucks speaks its responses aloud using these settings.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.system(size: 13, weight: .medium))

                ForEach(TTSProviderType.allCases) { provider in
                    Button {
                        selectedTTS = provider
                        selectedTTS.save()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(provider.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            Spacer()
                            if selectedTTS == provider {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTTS == provider ? Color.blue.opacity(0.12) : .white.opacity(0.04))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTTS == provider ? Color.blue.opacity(0.3) : .clear, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTTS == .elevenLabs {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice ID")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    TextField("21m00Tcm4TlvDq8ikWAM (Rachel)", text: $selectedVoice)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)) }
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1) }
                        .onChange(of: selectedVoice) { _, val in
                            UserDefaults.standard.set(val, forKey: "ttsVoiceId")
                        }
                }
            }

            if selectedTTS == .cartesia {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice ID (Cartesia)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    TextField("Enter Cartesia voice ID", text: $cartesiaVoiceId)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)) }
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1) }
                        .onChange(of: cartesiaVoiceId) { _, val in
                            UserDefaults.standard.set(val, forKey: "cartesiaVoiceId")
                        }

                    Text("Find voices at cartesia.ai. Use any voice ID from their library.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Speed")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text(String(format: "%.1f×", ttsSpeed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)
                }
                Slider(value: Binding(
                    get: { ttsSpeed },
                    set: {
                        ttsSpeed = $0
                        UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed")
                    }
                ), in: 0.5...2.0, step: 0.1)
                .tint(.blue)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @StateObject private var shortcutConfig = PushToTalkShortcutConfiguration.shared
    @State private var isCapturing = false
    @State private var shortcutEventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts")
                .font(.system(size: 18, weight: .semibold))

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Push-to-Talk")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 10) {
                    Button {
                        if isCapturing { stopCapture() } else { startCapture() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCapturing ? "keyboard.badge.ellipsis" : "keyboard")
                                .font(.system(size: 12))
                            Text(isCapturing ? "Press shortcut\u{2026}" : shortcutConfig.label)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .tint(isCapturing ? .blue : .white)

                    Button("Reset") {
                        stopCapture()
                        shortcutConfig.resetToDefault()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }

                Text("Hold this key combination to record, release to send.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Global Shortcuts")
                    .font(.system(size: 13, weight: .medium))

                shortcutRow(label: "Toggle Pucks Panel", key: "⌘ + Shift + P")
                shortcutRow(label: "Toggle Lens", key: "⌘ + Shift + L")
                shortcutRow(label: "Stop Speaking", key: "⌘ + Shift + S")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func shortcutRow(label: String, key: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.04)) }
    }

    private func startCapture() {
        stopCapture()
        isCapturing = true
        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let modifiers = PushToTalkShortcutConfiguration.captureModifiers(from: event.modifierFlags)
            let disallowed: Set<UInt16> = [UInt16(kVK_Command), UInt16(kVK_Shift), UInt16(kVK_Option), UInt16(kVK_Control)]
            guard !disallowed.contains(event.keyCode), modifiers != 0 else { return nil }
            shortcutConfig.update(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        isCapturing = false
        if let m = shortcutEventMonitor {
            NSEvent.removeMonitor(m)
            shortcutEventMonitor = nil
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @StateObject private var cursorConfig = CursorAppearanceConfiguration.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.system(size: 18, weight: .semibold))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Cursor Style")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 6) {
                    ForEach(CursorStyle.allCases) { style in
                        Button {
                            cursorConfig.style = style
                        } label: {
                            VStack(spacing: 4) {
                                cursorPreviewIcon(style)
                                    .frame(width: 28, height: 28)
                                Text(style.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(cursorConfig.style == style ? .white : .white.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(cursorConfig.style == style ? Color.blue.opacity(0.3) : .white.opacity(0.06))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(cursorConfig.style == style ? Color.blue.opacity(0.5) : .clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Text("Scale")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: $cursorConfig.scale, in: 0.6...2.0, step: 0.05)
                        .tint(.blue)
                    Text(cursorConfig.scale, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 32)
                }

                HStack(spacing: 8) {
                    Text("Distance")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                    Slider(value: $cursorConfig.distance, in: 10...80, step: 1)
                        .tint(.blue)
                    Text("\(Int(cursorConfig.distance))pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 36)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Panel")
                    .font(.system(size: 13, weight: .medium))

                Toggle(isOn: .constant(PanelPinState.shared.isPinned)) {
                    Text("Pin panel open by default")
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .tint(.blue)
                .disabled(true)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cursorPreviewIcon(_ style: CursorStyle) -> some View {
        switch style {
        case .triangle:
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
        case .arrow:
            Image(systemName: "arrow.up.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        case .dot:
            Circle()
                .fill(Color.blue)
                .frame(width: 14, height: 14)
        case .target:
            Image(systemName: "scope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        case .ring:
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 16, height: 16)
        case .diamond:
            Image(systemName: "diamond.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsView: View {
    @State private var micGranted = CompanionPermissionCenter.hasMicrophonePermission()
    @State private var screenGranted = false
    @State private var accessibilityGranted = CompanionPermissionCenter.hasAccessibilityPermission()
    @State private var speechGranted = CompanionPermissionCenter.hasSpeechRecognitionPermission()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.system(size: 18, weight: .semibold))

            Text("Pucks requires these macOS permissions to function. Grant them in System Settings if needed.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(spacing: 8) {
                permissionRow(
                    title: "Microphone",
                    description: "Required for voice input",
                    granted: micGranted,
                    action: requestMic
                )
                permissionRow(
                    title: "Screen Recording",
                    description: "Required for screen capture and cursor detection",
                    granted: screenGranted,
                    action: requestScreen
                )
                permissionRow(
                    title: "Accessibility",
                    description: "Required for cursor overlay and element detection",
                    granted: accessibilityGranted,
                    action: requestAccessibility
                )
                permissionRow(
                    title: "Speech Recognition",
                    description: "Required for Apple Speech transcription fallback",
                    granted: speechGranted,
                    action: requestSpeech
                )
            }

            HStack {
                Button {
                    refreshPermissions()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Spacer()

                Button {
                    openSystemSettings()
                } label: {
                    Label("Open System Settings", systemImage: "gear")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { refreshPermissions() }
    }

    @ViewBuilder
    private func permissionRow(title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(granted ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            if !granted {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(granted ? Color.green.opacity(0.06) : .white.opacity(0.04))
        }
    }

    private func refreshPermissions() {
        micGranted = CompanionPermissionCenter.hasMicrophonePermission()
        accessibilityGranted = CompanionPermissionCenter.hasAccessibilityPermission()
        speechGranted = CompanionPermissionCenter.hasSpeechRecognitionPermission()
        Task {
            screenGranted = await CompanionPermissionCenter.hasScreenRecordingPermissionAsync()
        }
    }

    private func requestMic() {
        CompanionPermissionCenter.requestMicrophonePermission { granted in
            micGranted = granted
        }
    }

    private func requestScreen() {
        SettingsWindowController.shared.temporarilyLowerLevel()
        CompanionPermissionCenter.requestScreenRecordingPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            screenGranted = await CompanionPermissionCenter.hasScreenRecordingPermissionAsync()
        }
    }

    private func requestAccessibility() {
        // Temporarily lower window level so the AX trust prompt is visible
        SettingsWindowController.shared.temporarilyLowerLevel()
        let granted = CompanionPermissionCenter.requestAccessibilityPermission()
        accessibilityGranted = granted
        if !granted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func requestSpeech() {
        CompanionPermissionCenter.requestSpeechRecognitionPermission { granted in
            speechGranted = granted
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
