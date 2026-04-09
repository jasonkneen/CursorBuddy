# CursorBuddy

> ⚠️ **Work in Progress** — CursorBuddy is under active development. Expect rough edges, breaking changes, and missing features. Contributions and feedback welcome.

This was previously called "Pucks" which is a diverged branch and in pucks-archive branch.

CursorBuddy (formerly Pucks) is a native macOS menu bar AI companion that lives in your system tray and helps you learn, think, and create through voice conversation. It can see your screen, hear you talk, point at things, and now execute tools on your behalf.

## What It Does

- **Push-to-talk AI assistant** — hold a hotkey, speak, get a response read back to you
- **Screen-aware** — captures your screen and cursor position so it understands what you're looking at
- **Cursor buddy** — an animated blue cursor that flies to and points at UI elements Claude references
- **Liquid Glass lens** — magnification lens that follows your cursor (macOS 26)
- **Built-in tools** — execute shell commands, read/write files, open apps/URLs, search files, clipboard access
- **MCP server support** — connect to external MCP servers (stdio + HTTP/SSE) to extend CursorBuddy with any tools
- **Multi-provider** — supports multiple transcription (OpenAI, Deepgram, AssemblyAI, Apple Speech) and TTS (ElevenLabs, Cartesia) providers

## Recent Changes (Unpushed)

### Rename: Pucks → CursorBuddy
- Full rename across all 35+ Swift files, bundle ID (`com.cursorbuddy.app`), Info.plist, entitlements, build scripts, system prompt, config paths (`~/.cursorbuddy/`)
- Sparkle feed URL, help URL, menu items, log prefixes all updated

### MCP Integration
- **MCP Swift SDK** (`modelcontextprotocol/swift-sdk`) integrated as a dependency
- **MCP Client Manager** — connects to external MCP servers, discovers tools, routes tool calls
- **Stdio transport** — spawn local processes (e.g. `npx @modelcontextprotocol/server-filesystem /tmp`)
- **HTTP/SSE transport** — connect to remote MCP servers
- **Settings UI** — new "MCP Servers" tab to add/remove/configure servers with status indicators and tool discovery

### Built-in Tools (Native, No MCP Required)
- `execute_command` — run shell commands via `/bin/zsh`
- `read_file` / `write_file` — read and write files on disk
- `list_directory` — list folder contents with types and sizes
- `search_files` — find files by glob pattern
- `open_url` / `open_application` — open URLs and launch apps
- `get_clipboard` / `set_clipboard` — clipboard read/write
- All tools are passed to Claude in every API request and executed when Claude calls them via the tool_use protocol

### Claude API Improvements
- Full tool_use loop: Claude requests tool → CursorBuddy executes → result sent back → Claude continues
- Handles streaming `content_block_start`, `input_json_delta`, `content_block_stop`, and `stop_reason: "tool_use"`
- Dead `computerUseResolutions` code removed

### Screen Capture Overhaul (Matching Clicky)
- Screenshots now capped at **1280px max dimension** (was native resolution — 4-5x smaller, much faster)
- Proper `screenshotWidthInPixels` vs `displayWidthInPoints` separation for accurate coordinate conversion
- Image labels include exact pixel dimensions so Claude knows the coordinate space
- Own app windows excluded from captures
- JPEG quality bumped to 0.8

### UI/UX Improvements
- Panel corner radius reduced to 16px
- Settings window: resizable, proper keyboard focus (`NSApp.setActivationPolicy(.regular)` for LSUIElement apps)
- Settings sidebar widened to 180px for "MCP Servers" tab
- Glass effects on cursor style picker, menu bar icon picker, and slider controls
- Mic button and status chip use blue-tinted glass with colored glow
- Streaming response overlay uses frosted material instead of opaque background
- Chat panel hides when Settings opens, restores on close
- API keys save in realtime (removed manual Save button)
- Chat layout restructured — fixed header, scrollable messages, fixed footer chin with mic

### CI/CD
- Xcode Cloud scripts (`ci_scripts/ci_post_clone.sh`, `ci_post_xcodebuild.sh`)
- GitHub Actions workflows: `build.yml` (push to main) and `release.yml` (tag-based release with signing + notarization)
- Shared Xcode scheme for CursorBuddy

## Architecture

```
CursorBuddy/
├── CursorBuddyApp.swift        # SwiftUI App entry point
├── CompanionAppDelegate.swift   # NSApplicationDelegate, manager orchestration
├── Info.plist                   # App config, permissions, Sparkle
├── CursorBuddy.entitlements     # Sandbox disabled for CGEvent tap + screen capture
├── MCP/                         # Model Context Protocol integration
│   ├── MCPClientManager         # Connects to MCP servers, aggregates tools
│   ├── MCPServerConfig          # Server config model + persistence
│   ├── MCPSettingsView          # Settings UI for MCP servers
│   └── BuiltInTools             # Native tools (shell, files, clipboard, etc.)
├── API/                         # API clients
│   ├── ClaudeAPI                # Anthropic Claude (streaming, tool_use loop)
│   ├── CodexAPI                 # OpenAI chat completions
│   ├── OpenAIAPI                # Whisper transcription
│   ├── ElevenLabsTTSClient      # ElevenLabs TTS
│   └── CartesiaTTSClient        # Cartesia real-time TTS
├── Audio/                       # Recording + transcription providers
├── Views/                       # SwiftUI views
├── Managers/                    # CompanionManager, FloatingSessionButton
├── Overlay/                     # Cursor overlay, response bubble, lens, PTT indicator
├── Utilities/                   # Permissions, hotkeys, screen capture, config
└── Resources/                   # AppIcon.icns
```

**Dependencies:**
- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-updates
- [PostHog](https://github.com/PostHog/posthog-ios) — analytics
- [PLCrashReporter](https://github.com/microsoft/plcrashreporter) — crash reporting
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) — Model Context Protocol client

## Building

### Prerequisites
- Xcode 26+ with macOS 26 SDK
- Swift 6.2+

### Quick Start
```bash
swift build
swift run CursorBuddy
```

### Dev Build & Install
```bash
./build-and-run.sh  # Builds, signs, installs to /Applications, launches
```

### API Keys
Configure in Settings → API Keys, or create `~/.cursorbuddy/keys.json`:
```json
{
    "ANTHROPIC_API_KEY": "sk-ant-...",
    "OPENAI_API_KEY": "sk-...",
    "ELEVENLABS_API_KEY": "...",
    "DEEPGRAM_API_KEY": "..."
}
```

### MCP Servers
Configure in Settings → MCP Servers. Example stdio server:
- Command: `npx`
- Arguments: `@modelcontextprotocol/server-filesystem`, `/tmp`

## Known Issues (WIP)
- Chat panel layout still needs polish — messages can overlap footer in some edge cases
- Permission flow needs testing on fresh installs
- MCP HTTP transport not yet tested with all server implementations
- Tool execution has no user confirmation step (planned)
- Conversation history stored in UserDefaults (should migrate to file-based storage)

## License

MIT
