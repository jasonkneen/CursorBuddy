# Pucks

Pucks is a native macOS menu bar AI companion that lives in your system tray and helps you learn, think, and create through voice conversation.

## What It Does

Pucks is a push-to-talk AI assistant that:

- Lives in the macOS menu bar (LSUIElement app — no dock icon)
- Captures your screen for visual context when you talk to it
- Transcribes your speech via AssemblyAI
- Sends your transcript + screenshot to Claude AI for intelligent responses
- Speaks responses back to you using ElevenLabs text-to-speech
- Supports global hotkeys for push-to-talk activation

## Architecture

```
Pucks/
├── PucksApp.swift            # SwiftUI App entry point, menu bar setup
├── Info.plist                 # App configuration, permissions, Sparkle config
├── Pucks.entitlements        # Sandbox disabled (CGEvent tap, screen capture)
├── Views/                     # SwiftUI views (settings, popover, overlays)
├── Managers/                  # Core business logic managers
│   ├── AudioManager           # Microphone recording, push-to-talk
│   ├── ScreenCaptureManager   # Screenshot capture via CGWindowList
│   ├── HotkeyManager         # Global hotkey registration (CGEvent tap)
│   ├── ConversationManager    # Orchestrates the talk → transcribe → AI → TTS flow
│   └── UpdateManager          # Sparkle auto-update integration
├── API/                       # API client code
│   ├── ClaudeAPI              # Anthropic Claude API (vision + text)
│   ├── AssemblyAIAPI          # Speech-to-text transcription
│   └── ElevenLabsAPI          # Text-to-speech synthesis
├── Audio/                     # Audio playback, AVAudioEngine utilities
├── Overlay/                   # Screen overlay views (recording indicator, etc.)
├── Utilities/                 # Helpers, extensions, constants
└── Resources/                 # Assets, sounds, icons
```

**Key technology choices:**
- **SwiftUI + AppKit** hybrid — SwiftUI for views, AppKit for menu bar, overlays, and system APIs
- **No sandbox** — required for CGEvent tap (global hotkeys) and screen capture
- **Universal binary** — runs natively on both Apple Silicon and Intel Macs
- **macOS 14.2+** minimum deployment target

**Dependencies:**
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-updates
- [PostHog](https://github.com/PostHog/posthog-ios) — analytics
- [PLCrashReporter](https://github.com/microsoft/plcrashreporter) — crash reporting

## Building

### Prerequisites
- Xcode 15+ with macOS 14.2+ SDK
- Swift 5.9+

### Build with Xcode
1. Open `Package.swift` in Xcode (File → Open → select Package.swift)
2. Select the "Pucks" scheme and "My Mac" as the run destination
3. Build and run (⌘R)

### Build from command line
```bash
swift build
swift run Pucks
```

### API Keys
You'll need to set these environment variables or configure them in the app's settings:
- `ANTHROPIC_API_KEY` — Claude API key
- `ASSEMBLYAI_API_KEY` — AssemblyAI API key
- `ELEVENLABS_API_KEY` — ElevenLabs API key

## License

MIT