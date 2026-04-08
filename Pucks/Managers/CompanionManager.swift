import Foundation
import SwiftUI
import Combine

// MARK: - Voice State

enum CompanionVoiceState: String, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

// MARK: - Conversation Turn

struct ConversationTurn: Identifiable, Codable {
    let id: UUID
    let userTranscript: String
    let assistantResponse: String
    let timestamp: Date
    let modelName: String

    init(userTranscript: String, assistantResponse: String, modelName: String = "Claude Sonnet 4") {
        self.id = UUID()
        self.userTranscript = userTranscript
        self.assistantResponse = assistantResponse
        self.timestamp = Date()
        self.modelName = modelName
    }
}

// MARK: - CompanionManager

@MainActor
class CompanionManager: ObservableObject {

    // MARK: - Published Properties

    @Published var conversationHistory: [ConversationTurn] = [] {
        didSet { persistConversation() }
    }
    @Published var isRecordingFromKeyboardShortcut: Bool = false
    @Published var isRecordingFromMicrophoneButton: Bool = false
    @Published var activeTurnTranscriptText: String = ""
    @Published var activeTurnOrder: Int = 0
    @Published var serverContext: String = ""
    @Published var voiceState: CompanionVoiceState = .idle {
        didSet {
            voiceStateObservable?.state = voiceState
            if oldValue == .listening && voiceState != .listening {
                voiceStateObservable?.clearAudioLevels()
            }
        }
    }

    // MARK: - Initializer

    init() {
        // Restore persisted conversation history
        if let data = UserDefaults.standard.data(forKey: "conversationHistory"),
           let history = try? JSONDecoder().decode([ConversationTurn].self, from: data) {
            self.conversationHistory = history
            print("[CompanionManager] Restored \(history.count) conversation turn(s) from previous session.")
        }

        // Listen for VAD stop events from BuddyDictationManager
        NotificationCenter.default.addObserver(
            forName: .vadSpeakingStopped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                // VAD detected silence — stop the recording session
                if self.voiceState == .listening || self.voiceState == .thinking {
                    print("[CompanionManager] VAD triggered stop.")
                    self.stopSession()
                }
            }
        }
    }

    // MARK: - Screenshot Interceptor

    lazy var screenshotInterceptor: ScreenshotInterceptor = {
        ScreenshotInterceptor()
    }()

    /// Screenshots the user has explicitly added to the next chat turn
    @Published var attachedScreenshots: [CapturedScreenshot] = []

    func attachPendingScreenshot() {
        guard let screenshot = screenshotInterceptor.pendingScreenshot else { return }
        attachedScreenshots.append(screenshot)
        screenshotInterceptor.dismiss()
        print("[CompanionManager] Screenshot attached to chat (\(attachedScreenshots.count) total).")
    }

    func removeAttachedScreenshot(_ id: UUID) {
        attachedScreenshots.removeAll { $0.id == id }
    }

    func attachDroppedImage(_ nsImage: NSImage) {
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        let base64 = jpegData.base64EncodedString()
        let screenshot = CapturedScreenshot(image: nsImage, base64JPEG: base64, source: .file)
        attachedScreenshots.append(screenshot)
        print("[CompanionManager] Dropped image attached (\(attachedScreenshots.count) total).")
    }

    // MARK: - Sub-Managers (set by AppDelegate)

    var elementDetector: ElementLocationDetector?
    var selectedTextMonitor: SelectedTextMonitor?
    var pttOverlayManager: GlobalPushToTalkOverlayManager?
    var voiceStateObservable: VoiceStateObservable? {
        didSet { subscribeToAudioLevels() }
    }

    private var audioLevelCancellable: AnyCancellable?

    // MARK: - Lazy Sub-Managers

    lazy var claudeAPI: ClaudeAPI = {
        ClaudeAPI()
    }()

    lazy var ttsClient: TTSClient = {
        TTSClient.shared
    }()

    lazy var dictationManager: BuddyDictationManager = {
        BuddyDictationManager()
    }()

    lazy var screenCapture: CompanionScreenCapture = {
        CompanionScreenCapture()
    }()

    // MARK: - Audio Level → Waveform Bridge

    private func subscribeToAudioLevels() {
        audioLevelCancellable?.cancel()
        guard let vsObs = voiceStateObservable else { return }
        audioLevelCancellable = dictationManager.$audioPowerLevel
            .receive(on: RunLoop.main)
            .sink { [weak vsObs] level in
                vsObs?.pushAudioLevel(level)
            }
    }

    // MARK: - Session Control

    /// Active processing task — cancelled on interruption
    private var processingTask: Task<Void, Never>?

    /// Begin push-to-talk recording session (interruptible from any state)
    func startSession() async throws {
        // Interrupt any in-progress processing/speaking
        if voiceState == .thinking || voiceState == .speaking {
            print("[CompanionManager] Interrupting current state: \(voiceState)")
            processingTask?.cancel()
            processingTask = nil
            ttsClient.stopPlayback()
            elementDetector?.resetDetection()
            OverlayWindowManager.shared.overlayMode = .idle
        } else if voiceState == .listening {
            // Already listening — treat as a no-op or stop+restart
            print("[CompanionManager] Already listening, ignoring duplicate start")
            return
        }

        activeTurnTranscriptText = ""
        activeTurnOrder += 1

        let isKeyboard = isRecordingFromKeyboardShortcut
        print("[CompanionManager] Recording started (keyboard: \(isKeyboard))")

        do {
            try await dictationManager.startRecording()
        } catch {
            voiceState = .idle
            throw error
        }

        // If the key was already released while recording was spinning up, cancel cleanly.
        if isKeyboard && !isRecordingFromKeyboardShortcut {
            dictationManager.cancelRecording()
            voiceState = .idle
            print("[CompanionManager] Recording cancelled before listen state became active.")
            return
        }

        voiceState = .listening
    }

    /// Stop recording and process the turn
    /// Cancel thinking/speaking and return to idle.
    func cancelCurrentResponse() {
        processingTask?.cancel()
        processingTask = nil
        ttsClient.stopPlayback()
        elementDetector?.resetDetection()
        OverlayWindowManager.shared.overlayMode = .idle
        voiceState = .idle
        print("[CompanionManager] Response cancelled by user.")
    }

    func stopSession() {
        if !dictationManager.isRecording && voiceState != .listening {
            return
        }

        print("[CompanionManager] Recording stopped, processing...")
        isRecordingFromKeyboardShortcut = false
        isRecordingFromMicrophoneButton = false

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            let transcript = await self.dictationManager.stopRecording()
            print("[CompanionManager] Transcript: \"\(transcript ?? "nil")\"")

            guard let transcript = transcript, !transcript.isEmpty else {
                self.voiceState = .idle
                self.pttOverlayManager?.hide()
                print("[CompanionManager] No transcript received.")
                return
            }

            self.activeTurnTranscriptText = transcript
            self.processingTask = Task { @MainActor in
                await self.handleTranscript(text: transcript)
            }
        }
    }

    func suggestForSelectedText() {
        guard voiceState == .idle || voiceState == .speaking else { return }
        guard let selectedText = selectedTextMonitor?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else { return }

        processingTask?.cancel()
        processingTask = Task { @MainActor in
            await handleTranscript(text: "Suggest improvements for the selected text.")
        }
    }

    /// Process transcript: screenshot -> Claude API -> parse response -> TTS
    func handleTranscript(text: String) async {
        voiceState = .thinking

        // 1. Capture screenshots of all screens
        var screenshots: [ScreenCapture] = []
        if CompanionPermissionCenter.hasScreenRecordingPermission() {
            do {
                screenshots = try await screenCapture.captureScreen()
                print("[CompanionManager] Captured \(screenshots.count) screenshot(s).")
            } catch {
                print("[CompanionManager] Screenshot capture failed: \(error)")
            }
        } else {
            print("[CompanionManager] Screen recording permission missing; continuing without screenshots.")
        }

        // 2. Build conversation messages for Claude API
        _ = conversationHistory.map { turn in
            [
                ["role": "user", "content": turn.userTranscript],
                ["role": "assistant", "content": turn.assistantResponse]
            ]
        }.flatMap { $0 }

        // 3. Prepare base64 images
        let base64Images = screenshots.compactMap { capture -> (label: String, base64: String, cursorX: Int, cursorY: Int)? in
            guard let base64 = capture.base64JPEG else { return nil }
            return (label: capture.label, base64: base64, cursorX: capture.cursorInImageX, cursorY: capture.cursorInImageY)
        }

        // 4. Send to Claude API
        do {
            var allMessages: [ClaudeAPI.Message] = []
            for turn in conversationHistory {
                allMessages.append(ClaudeAPI.Message(role: "user", content: turn.userTranscript))
                allMessages.append(ClaudeAPI.Message(role: "assistant", content: turn.assistantResponse))
            }

            // Append context so Claude knows where the user is focused
            var userText = text
            var contextParts: [String] = []
            
            // 1. Cursor position (highest priority context)
            if let primary = base64Images.first {
                contextParts.append("IMPORTANT: the user's mouse cursor is at pixel coordinates (\(primary.cursorX), \(primary.cursorY)) in the screenshot. you will see a RED CIRCLE and crosshair drawn around the cursor position in the image. when they say 'this', 'here', 'what is this', 'what does this do', etc., they are referring to what's at or near the red circle. look at what's inside or immediately adjacent to that circle.")
            }
            
            // 2. Frontmost app + window title + focused element
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                let appName = frontApp.localizedName ?? "Unknown"
                var windowTitle = ""
                var focusedElementInfo = ""
                
                // Get the focused window title via Accessibility API
                let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
                var focusedWindow: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
                    var titleValue: AnyObject?
                    if AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleValue) == .success {
                        windowTitle = (titleValue as? String) ?? ""
                    }
                    
                    // Try to get the focused element's description/title/value
                    var focusedElement: AnyObject?
                    if AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success {
                        let element = focusedElement as! AXUIElement
                        
                        // Try to get role and description
                        var roleValue: AnyObject?
                        var descValue: AnyObject?
                        var labelValue: AnyObject?
                        
                        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
                        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
                        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &labelValue)
                        
                        var elementParts: [String] = []
                        if let role = roleValue as? String {
                            elementParts.append(role)
                        }
                        if let label = labelValue as? String, !label.isEmpty {
                            elementParts.append("'\(label)'")
                        }
                        if let desc = descValue as? String, !desc.isEmpty {
                            elementParts.append(desc)
                        }
                        
                        if !elementParts.isEmpty {
                            focusedElementInfo = " The keyboard focus is on: \(elementParts.joined(separator: " - "))."
                        }
                    }
                }
                
                let windowInfo = windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)"
                contextParts.append("the user's frontmost/active window is: \(windowInfo). this is the window in front of all others.\(focusedElementInfo) if they ask about something without being specific, assume they mean something in this window, especially near their cursor.")
            }
            
            // 3. Add spatial awareness reminder
            contextParts.append("when the user says 'what is this' or 'what does this do' or points to something, look at what's near their cursor coordinates. that's what they're asking about. always prioritize cursor position when interpreting vague references.")

            if let selectedText = selectedTextMonitor?.selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
               !selectedText.isEmpty {
                contextParts.append("the user currently has text selected. treat that selected text as a strong focus target for editing, rewriting, summarizing, or suggestion requests. selected text: \"\(selectedText.prefix(800))\"")
            }
            
            // Append all context as a single block
            if !contextParts.isEmpty {
                userText += "\n\n[CONTEXT:\n" + contextParts.map { "• \($0)" }.joined(separator: "\n") + "\n]"
            }
            
            allMessages.append(ClaudeAPI.Message(role: "user", content: userText))

            var screenshotBase64s = base64Images.map { $0.base64 }
            var screenLabels = base64Images.map { $0.label }

            // Include user-attached screenshots
            for (index, attached) in attachedScreenshots.enumerated() {
                screenshotBase64s.append(attached.base64JPEG)
                screenLabels.append("user-attached screenshot \(index + 1) (\(attached.source.rawValue))")
            }
            if !attachedScreenshots.isEmpty {
                print("[CompanionManager] Including \(attachedScreenshots.count) user-attached screenshot(s).")
                userText += "\n[The user has attached \(attachedScreenshots.count) screenshot(s) to this message. Refer to them if relevant.]"
            }
            // Clear attached screenshots after use
            attachedScreenshots.removeAll()

            let responseStream = claudeAPI.sendMessage(
                messages: allMessages,
                screenshots: screenshotBase64s,
                screenLabels: screenLabels
            )

            var response = ""
            for try await chunk in responseStream {
                response += chunk
            }

            print("[CompanionManager] Claude response received (\(response.count) chars).")

            // 5. Parse all [POINT:x,y:label] tags via ElementLocationDetector
            let parsed = elementDetector?.parse(responseText: response)
            let cleanedText = parsed?.cleanedText ?? response

            // 6. Store conversation turn
            let turn = ConversationTurn(userTranscript: text, assistantResponse: response)
            conversationHistory.append(turn)

            // 7. Convert parsed points from screenshot pixel coords to overlay/screen coords
            let primaryCapture = screenshots.first(where: { $0.label.hasPrefix("primary focus") }) ?? screenshots.first
            let overlayPoints: [(point: CGPoint, label: String?)] = (parsed?.points ?? []).map { entry in
                guard let capture = primaryCapture else { return entry }
                let op = capture.screenshotPointToOverlayPoint(entry.point)
                print("[CompanionManager] POINT \(entry.point) → overlay \(op)")
                return (op, entry.label)
            }

            // 8. Hide PTT overlay
            pttOverlayManager?.hide()
            voiceState = .speaking

            if overlayPoints.isEmpty {
                // No points — just speak
                let _ = try await ttsClient.speak(text: cleanedText)
            } else {
                // Run cursor tour concurrently with TTS so the pointer moves while Claude speaks.
                // Each point gets ~2.5 s of screen time; we cancel the tour when TTS finishes.
                let detector = elementDetector
                let tourTask = Task { @MainActor in
                    OverlayWindowManager.shared.overlayMode = .navigating
                    for (index, entry) in overlayPoints.enumerated() {
                        if Task.isCancelled { break }
                        detector?.navigateTo(point: entry.point, label: entry.label)
                        // Pause between points (skip delay after the last one)
                        if index < overlayPoints.count - 1 {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                        }
                    }
                }

                let _ = try await ttsClient.speak(text: cleanedText)
                tourTask.cancel()

                // Return cursor and go idle
                elementDetector?.returnToCursor()
                try? await Task.sleep(nanoseconds: 800_000_000)
                OverlayWindowManager.shared.overlayMode = .idle
            }

            voiceState = .idle
            print("[CompanionManager] TTS playback complete.")
        } catch {
            print("[CompanionManager] Claude API error: \(error)")
            pttOverlayManager?.hide()
            voiceState = .idle
        }
    }

    // MARK: - Point Tag Parsing

    /// Parse [POINT:x,y] tags from Claude's response
    private func parsePointTags(from text: String) -> (cleanedText: String, points: [CGPoint]) {
        var points: [CGPoint] = []
        var cleanedText = text

        let pattern = #"\[POINT:(\d+(?:\.\d+)?),(\d+(?:\.\d+)?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (cleanedText, points)
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        for match in matches.reversed() {
            if let xRange = Range(match.range(at: 1), in: text),
               let yRange = Range(match.range(at: 2), in: text),
               let x = Double(text[xRange]),
               let y = Double(text[yRange]) {
                points.insert(CGPoint(x: x, y: y), at: 0)
            }
            if let fullRange = Range(match.range, in: text) {
                cleanedText.removeSubrange(fullRange)
            }
        }

        return (cleanedText.trimmingCharacters(in: .whitespacesAndNewlines), points)
    }

    // MARK: - Cursor Animation

    private func animateCursor(to point: CGPoint) {
        print("[CompanionManager] Animating cursor to \(point)")
        let steps = 20
        let duration: TimeInterval = 0.3
        let currentPosition = NSEvent.mouseLocation

        // Convert from screen coordinates (origin bottom-left) to CGEvent coordinates (origin top-left)
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height
        let startY = screenHeight - currentPosition.y
        let startPoint = CGPoint(x: currentPosition.x, y: startY)
        let endPoint = point

        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let eased = t * t * (3.0 - 2.0 * t) // smoothstep
            let x = startPoint.x + (endPoint.x - startPoint.x) * eased
            let y = startPoint.y + (endPoint.y - startPoint.y) * eased

            DispatchQueue.main.asyncAfter(deadline: .now() + duration * t) {
                let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
                moveEvent?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Reset

    func clearConversation() {
        conversationHistory.removeAll()
        activeTurnTranscriptText = ""
        activeTurnOrder = 0
        serverContext = ""
        voiceState = .idle
        // didSet on conversationHistory persists the empty array
        print("[CompanionManager] Conversation cleared.")
    }

    // MARK: - Conversation Persistence

    private func persistConversation() {
        if let data = try? JSONEncoder().encode(conversationHistory) {
            UserDefaults.standard.set(data, forKey: "conversationHistory")
        }
    }
}
