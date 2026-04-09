/**
 * Electron Main Process
 *
 * Three pieces:
 * 1. Tray icon — click to toggle the control panel
 * 2. Overlay — small transparent 320×80, follows cursor, click-through
 * 3. Panel — frameless, rounded, transparent settings + playground
 *
 * Cross-platform: macOS, Windows, Linux.
 */

const { app, BrowserWindow, Tray, Menu, screen, ipcMain, nativeImage, globalShortcut, clipboard, session } = require("electron");
const path = require("path");
const { execFile } = require("child_process");
const { captureAllScreens, screenshotPointToScreenCoords, setCalibration } = require("./services/capture.js");
const { runInference, runComputerUse, clearHistory } = require("./services/inference.js");
const mcpServer = require("./services/mcp-server.js");
const transcription = require("./services/transcription.js");
const tts = require("./services/tts.js");
const { VoiceResponsePipeline } = require("./services/voice-response.js");
const mcpClient = require("./services/mcp-client.js");
const toolLoader = require("./services/tool-loader.js");
const { getSystemTools } = require("./services/system-actions.js");
const { sendToOverlay, sendToPanel, broadcast, setWindows, getOverlayWindow, getPanelWindow } = require("./lib/ipc-helpers.js");
const { loadSettings, saveSettings } = require("./lib/settings-cache.js");
const { parsePointingCoordinates } = require("./lib/point-parser.js");
const log = require("./lib/session-logger.js");

// ── Constants (must match design-tokens.ts) ───────────────────
const VIEWPORT_WIDTH = 320;
const VIEWPORT_HEIGHT = 80;
const LOCAL_BUDDY_X = 24;
const LOCAL_BUDDY_Y = 40;

const PANEL_WIDTH = 680;
const PANEL_HEIGHT = 580;

let tray = null;
let isFollowingCursor = true;
let cursorTrackingInterval = null;
let lastCursorDisplayId = null;

// ── Screen Bounds ─────────────────────────────────────────────

function getCursorScreenBounds() {
  const cursorPoint = screen.getCursorScreenPoint();
  const cursorDisplay = screen.getDisplayNearestPoint(cursorPoint);
  return {
    x: cursorDisplay.bounds.x,
    y: cursorDisplay.bounds.y,
    width: cursorDisplay.bounds.width,
    height: cursorDisplay.bounds.height,
  };
}

function broadcastScreenBounds() {
  broadcast("screen-bounds", getCursorScreenBounds());
}

// ── Tray Icon ─────────────────────────────────────────────────

function createTray() {
  const trayIconPath = path.join(__dirname, "icons", "tray-22.png");
  let trayIcon;
  if (require("fs").existsSync(trayIconPath)) {
    trayIcon = nativeImage.createFromPath(trayIconPath);
  } else {
    trayIcon = nativeImage.createFromDataURL(
      `data:image/svg+xml,` + encodeURIComponent(
        `<svg width="16" height="16" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="6" fill="#3b82f6"/></svg>`
      )
    );
  }

  tray = new Tray(trayIcon);
  tray.setToolTip("CursorBuddy");
  tray.on("click", (_event, bounds) => togglePanel(bounds));

  const contextMenu = Menu.buildFromTemplate([
    { label: "Toggle Panel", click: () => togglePanel(tray.getBounds()) },
    { type: "separator" },
    { label: "Quit CursorBuddy", click: () => app.quit() },
  ]);
  tray.setContextMenu(contextMenu);
}

function togglePanel(trayBounds) {
  const panelWindow = getPanelWindow();
  if (!panelWindow || panelWindow.isDestroyed()) {
    createPanelWindow(trayBounds);
  } else if (panelWindow.isVisible()) {
    panelWindow.hide();
  } else {
    positionPanelNearTray(trayBounds);
    panelWindow.show();
  }
}

function positionPanelNearTray(trayBounds) {
  const panelWindow = getPanelWindow();
  if (!panelWindow || panelWindow.isDestroyed()) return;
  const panelBounds = panelWindow.getBounds();
  let x = Math.round(trayBounds.x + trayBounds.width / 2 - panelBounds.width / 2);
  let y;
  if (process.platform === "darwin") {
    y = trayBounds.y + trayBounds.height + 4;
  } else {
    y = trayBounds.y - panelBounds.height - 4;
  }
  const displayBounds = screen.getDisplayNearestPoint({ x, y }).workArea;
  x = Math.max(displayBounds.x, Math.min(x, displayBounds.x + displayBounds.width - panelBounds.width));
  y = Math.max(displayBounds.y, Math.min(y, displayBounds.y + displayBounds.height - panelBounds.height));
  panelWindow.setPosition(x, y);
}

// ── Windows ───────────────────────────────────────────────────

function createOverlayWindow() {
  const isDev = !app.isPackaged;
  const overlayWindow = new BrowserWindow({
    width: VIEWPORT_WIDTH,
    height: VIEWPORT_HEIGHT,
    transparent: true,
    frame: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    hasShadow: false,
    resizable: false,
    focusable: false,
    type: "panel",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  overlayWindow.setIgnoreMouseEvents(true);
  overlayWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  overlayWindow.setAlwaysOnTop(true, "screen-saver");
  if (isDev) {
    overlayWindow.loadURL("http://localhost:1420");
  } else {
    overlayWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }
  overlayWindow.webContents.on("did-finish-load", () => broadcastScreenBounds());
  mcpServer.setOverlayWindow(overlayWindow);
  overlayWindow.on("closed", () => {
    setWindows(null, getPanelWindow());
    mcpServer.setOverlayWindow(null);
    stopCursorTracking();
  });

  // Register with IPC helper
  setWindows(overlayWindow, getPanelWindow());
  return overlayWindow;
}

function createPanelWindow(trayBounds) {
  const panelWindow = new BrowserWindow({
    width: PANEL_WIDTH,
    height: PANEL_HEIGHT,
    resizable: true,
    minWidth: 420,
    minHeight: 300,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    hasShadow: false,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload-panel.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  panelWindow.loadFile(path.join(__dirname, "panel.html"));
  panelWindow.webContents.on("did-finish-load", () => {
    broadcastScreenBounds();
    if (trayBounds) positionPanelNearTray(trayBounds);
    panelWindow.show();
  });
  panelWindow.on("close", (event) => {
    if (!app.isQuitting) { event.preventDefault(); panelWindow.hide(); }
  });

  // Register with IPC helper
  setWindows(getOverlayWindow(), panelWindow);
  return panelWindow;
}

// ── Cursor Tracking ───────────────────────────────────────────

function startCursorTracking() {
  cursorTrackingInterval = setInterval(() => {
    const overlayWindow = getOverlayWindow();
    if (!overlayWindow || overlayWindow.isDestroyed()) return;
    const cursorPoint = screen.getCursorScreenPoint();
    const currentDisplay = screen.getDisplayNearestPoint(cursorPoint);
    if (currentDisplay.id !== lastCursorDisplayId) {
      lastCursorDisplayId = currentDisplay.id;
      broadcastScreenBounds();
    }
    sendToOverlay("cursor-position", { x: cursorPoint.x, y: cursorPoint.y });
  }, 16);
}

function stopCursorTracking() {
  if (cursorTrackingInterval) { clearInterval(cursorTrackingInterval); cursorTrackingInterval = null; }
}

// ── IPC: Overlay ──────────────────────────────────────────────

ipcMain.on("set-window-position", (_event, pos) => {
  try {
    const overlayWindow = getOverlayWindow();
    if (!overlayWindow || overlayWindow.isDestroyed()) return;
    if (!pos || typeof pos !== "object") return;
    const x = parseInt(pos.x, 10);
    const y = parseInt(pos.y, 10);
    if (isNaN(x) || isNaN(y)) return;
    overlayWindow.setPosition(x, y);
  } catch (_) {}
});

ipcMain.on("set-following-cursor", (_event, following) => {
  isFollowingCursor = following;
});

ipcMain.on("panel:overlay-command", (_event, command, payload) => {
  // Intercept calibration updates
  if (command === "config:update" && payload && payload.calibration !== undefined) {
    setCalibration(payload.calibration);
    console.log("[Calibration] Updated:", JSON.stringify(payload.calibration));
  }
  // Intercept PTT shortcut changes — re-register the global shortcut
  if (command === "ptt-shortcut-updated" && payload && payload.shortcut) {
    registerPushToTalk(); // Re-reads settings and re-registers
    return;
  }
  sendToOverlay("overlay-command", command, payload);
});

ipcMain.on("panel:hide", () => {
  const panelWindow = getPanelWindow();
  if (panelWindow && !panelWindow.isDestroyed()) panelWindow.hide();
});

// ── IPC: Settings ─────────────────────────────────────────────

ipcMain.handle("settings:load", () => loadSettings());

ipcMain.handle("settings:save", (_event, settings) => {
  saveSettings(settings);
  return true;
});

ipcMain.handle("get-screen-bounds", () => getCursorScreenBounds());

ipcMain.handle("get-cursor-position", () => {
  const p = screen.getCursorScreenPoint();
  return { x: p.x, y: p.y };
});

ipcMain.handle("get-debug-info", () => {
  const p = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(p);
  const displays = screen.getAllDisplays();
  const screenIndex = displays.findIndex(d => d.id === display.id);

  // Get frontmost app name via AppleScript (macOS only)
  let activeApp = "—";
  if (process.platform === "darwin") {
    try {
      const { execFileSync } = require("child_process");
      activeApp = execFileSync("osascript", ["-e", 'tell application "System Events" to get name of first application process whose frontmost is true'], { timeout: 500 }).toString().trim();
    } catch (_) {}
  }

  return {
    cursor: { x: p.x, y: p.y },
    screen: { id: display.id, index: screenIndex + 1, total: displays.length, width: display.bounds.width, height: display.bounds.height, scale: display.scaleFactor },
    activeApp,
  };
});

// Calibration target window — shows a red crosshair at exact screen coords
let calTargetWindow = null;

ipcMain.handle("cal:show-target", (_event, x, y) => {
  if (calTargetWindow && !calTargetWindow.isDestroyed()) calTargetWindow.close();
  const size = 60;
  calTargetWindow = new BrowserWindow({
    width: size, height: size,
    x: Math.round(x - size/2), y: Math.round(y - size/2),
    transparent: true, frame: false, alwaysOnTop: true,
    skipTaskbar: true, hasShadow: false, focusable: false,
    resizable: false,
    webPreferences: { contextIsolation: true },
  });
  calTargetWindow.setIgnoreMouseEvents(true);
  calTargetWindow.setAlwaysOnTop(true, "screen-saver");
  calTargetWindow.loadURL(`data:text/html,<html><body style="margin:0;background:transparent"><svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><circle cx="${size/2}" cy="${size/2}" r="20" fill="none" stroke="red" stroke-width="3"/><line x1="${size/2-25}" y1="${size/2}" x2="${size/2+25}" y2="${size/2}" stroke="red" stroke-width="2"/><line x1="${size/2}" y1="${size/2-25}" x2="${size/2}" y2="${size/2+25}" stroke="red" stroke-width="2"/><circle cx="${size/2}" cy="${size/2}" r="3" fill="red"/></svg></body></html>`);
  return { ok: true };
});

ipcMain.handle("cal:hide-target", () => {
  if (calTargetWindow && !calTargetWindow.isDestroyed()) calTargetWindow.close();
  calTargetWindow = null;
  return { ok: true };
});

// ── IPC: Screen Capture ───────────────────────────────────

ipcMain.handle("capture-screens", async () => {
  try {
    return await captureAllScreens();
  } catch (err) {
    console.error("[Capture] Failed:", err.message);
    return [];
  }
});

// ── IPC: Inference ────────────────────────────────────────

/** Last captured screens — kept so we can scale POINT coords after inference */
let lastCapturedScreens = [];
let activeVoicePipeline = null;

ipcMain.on("inference:run", async (_event, { transcript, provider, model, attachments, voiceMode }) => {
  // Cancel any existing voice pipeline
  if (activeVoicePipeline) { activeVoicePipeline.cancel(); activeVoicePipeline = null; }
  try {
    const settings = loadSettings();
    log.event("inference:start", {
      transcript: transcript?.slice(0, 120),
      provider: provider || settings.chatProvider || "anthropic",
      model: model || settings.chatModel || "claude-sonnet-4-6",
      voiceMode: !!voiceMode,
      attachments: attachments?.length || 0,
    });
    const screens = await captureAllScreens();
    // Add any manually attached screenshots (from clipboard intercept)
    if (attachments && attachments.length > 0) {
      attachments.forEach((b64, i) => {
        screens.push({
          imageDataBase64: b64,
          label: `user-attached screenshot ${i + 1} (ask about this)`,
          isCursorScreen: false,
          displayWidthPx: 0, displayHeightPx: 0,
          displayX: 0, displayY: 0,
          screenshotWidthPx: 0, screenshotHeightPx: 0,
          scaleX: 1, scaleY: 1, scaleFactor: 1,
          cursorX: 0, cursorY: 0,
        });
      });
    }
    lastCapturedScreens = screens;

    let fullResponseText = "";
    const cursorScreen = screens.find(s => s.isCursorScreen) || screens[0];

    // Gather all available tools (system actions + MCP client + pi-compatible)
    const allTools = [
      ...getSystemTools(),
      ...mcpClient.getAllTools(),
      ...toolLoader.getToolList(),
    ];

    // Voice mode: synchronized TTS + text reveal + cursor pointing pipeline
    let voicePipeline = null;
    if (voiceMode) {
      voicePipeline = new VoiceResponsePipeline({
        onSpeakStart: () => {
          log.event("voice:speak_start");
          sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "responding" });
        },
        onSpeakEnd: () => {
          log.event("voice:speak_end");
          sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "idle" });
          broadcast("inference:chunk", { type: "done" });
        },
        onPointAt: (point) => {
          if (cursorScreen && point.imgX !== undefined) {
            const sc = screenshotPointToScreenCoords(point.imgX, point.imgY, cursorScreen);
            const flyPayload = { x: Math.round(sc.x), y: Math.round(sc.y), label: point.label, bubbleText: point.bubbleText };
            log.event("voice:cursor_fly", { imgX: point.imgX, imgY: point.imgY, screenX: flyPayload.x, screenY: flyPayload.y, label: point.label });
            sendToOverlay("overlay-command", "cursor:fly-to", flyPayload);
            sendToPanel("inference:chunk", { type: "done", scaledPoint: flyPayload });
          }
        },
        onRevealText: (accumulatedCleanText) => {
          // Progressive reveal: text appears sentence-by-sentence in sync with TTS
          sendToPanel("inference:chunk", { type: "text", text: accumulatedCleanText });
        },
        speak: async (sentenceText) => {
          try {
            const result = await tts.speak(sentenceText, settings);
            if (!result) return null;
            const audioBase64 = result.audioData.toString("base64");
            const audioPayload = { type: "voice:audio", audioBase64, mimeType: result.mimeType };
            sendToPanel("voice:audio-chunk", audioPayload);
            return { audioBase64, mimeType: result.mimeType, audioSizeBytes: result.audioData.length };
          } catch (err) {
            console.error("[VoicePipeline] TTS error:", err.message);
            return null;
          }
        },
      });
      activeVoicePipeline = voicePipeline;
    }

    await runInference({
      provider: provider || settings.chatProvider || "anthropic",
      model: model || settings.chatModel || "claude-sonnet-4-6",
      transcript,
      screens,
      settings,
      mcpTools: allTools.length > 0 ? allTools : undefined,
      onChunk: async (chunk) => {
        if (chunk.type === "text") {
          fullResponseText = chunk.text || "";
        }

        // On done: voice pipeline handles TTS+pointing, text mode does POINT parsing
        if (chunk.type === "done") {
          if (voicePipeline) {
            // Voice mode: feed text and start synchronized playback.
            // Don't broadcast this "done" — the pipeline's onSpeakEnd will
            // send "done" when all audio finishes playing.
            voicePipeline.feedText(fullResponseText);
            voicePipeline.finish();
            activeVoicePipeline = null;
            return; // skip the broadcast() below — pipeline owns the timing now
          } else if (fullResponseText) {
            // Text mode: parse POINT tag using shared parser
            const parsed = parsePointingCoordinates(fullResponseText);
            if (parsed.coordinate) {
              const targetScreenIndex = parsed.screenNumber
                ? Math.max(0, Math.min(parsed.screenNumber - 1, lastCapturedScreens.length - 1))
                : -1;
              const targetScreen = targetScreenIndex >= 0
                ? lastCapturedScreens[targetScreenIndex]
                : (lastCapturedScreens.find(s => s.isCursorScreen) || lastCapturedScreens[0]);

              if (targetScreen) {
                const sc = screenshotPointToScreenCoords(parsed.coordinate.x, parsed.coordinate.y, targetScreen);
                log.event("inference:point_detected", { imgX: parsed.coordinate.x, imgY: parsed.coordinate.y, screenX: Math.round(sc.x), screenY: Math.round(sc.y), label: parsed.elementLabel });
                const cursorBubbleText = parsed.spokenText.length > 80
                  ? parsed.spokenText.slice(0, 77).replace(/\s+\S*$/, "") + "\u2026"
                  : parsed.spokenText;
                chunk.scaledPoint = {
                  x: Math.round(sc.x), y: Math.round(sc.y),
                  label: parsed.elementLabel || "element",
                  bubbleText: cursorBubbleText,
                };
              }
            }

            // Fallback: computer use if no POINT and CU configured
            if (!chunk.scaledPoint && settings.cuProvider && settings.cuModel && cursorScreen) {
              try {
                const cuResult = await runComputerUse({
                  userQuestion: transcript,
                  assistantResponse: fullResponseText,
                  screenCapture: cursorScreen,
                  settings,
                  onChunk: (cuChunk) => broadcast("inference:chunk", cuChunk),
                });
                if (cuResult.coordinate) {
                  const cleanText = fullResponseText.replace(/\s*\[POINT:[^\]]*\]\s*/g, '').trim();
                  const bubbleText = cleanText.length > 80
                    ? cleanText.slice(0, 77).replace(/\s+\S*$/, '') + '\u2026'
                    : cleanText;
                  chunk.scaledPoint = {
                    x: cuResult.coordinate[0], y: cuResult.coordinate[1],
                    label: 'element', bubbleText,
                  };
                }
              } catch (cuErr) {
                console.error('[CU] Failed:', cuErr.message);
                broadcast('inference:chunk', { type: 'tool_result', name: 'computer_use', result: 'Error: ' + cuErr.message });
              }
            }
          }
        }

        broadcast("inference:chunk", chunk);
      },
    });
  } catch (err) {
    log.error("inference:error", err);
    broadcast("inference:chunk", { type: "error", error: err.message });
  }
});

ipcMain.on("inference:clear-history", () => clearHistory());

// ── IPC: Transcription ────────────────────────────────────────

ipcMain.handle("stt:start", async (_event, provider) => {
  const settings = loadSettings();
  const sttProvider = provider || settings.sttProvider || "assemblyai";
  log.event("stt:start", { provider: sttProvider });
  try {
    await transcription.startSession(
      provider || settings.sttProvider || "assemblyai",
      settings,
      (text) => broadcast("stt:transcript", { text, isFinal: false }),
      (text) => broadcast("stt:transcript", { text, isFinal: true }),
      (err) => broadcast("stt:error", err.message || String(err))
    );
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.on("stt:audio", (_event, pcm16ArrayBuffer) => {
  transcription.sendAudio(Buffer.from(pcm16ArrayBuffer));
});

ipcMain.on("stt:request-final", () => {
  transcription.requestFinal();
});

ipcMain.on("stt:stop", () => {
  log.event("stt:stop");
  transcription.stopSession();
});

// ── IPC: TTS ──────────────────────────────────────────────────

ipcMain.handle("tts:speak", async (_event, text) => {
  const settings = loadSettings();
  log.event("tts:request", { textLength: text?.length, provider: settings.ttsProvider || "elevenlabs" });
  try {
    const result = await tts.speak(text, settings);
    if (!result) return { ok: false, error: "Empty text" };
    return {
      ok: true,
      audioBase64: result.audioData.toString("base64"),
      mimeType: result.mimeType,
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

// ── IPC: MCP Client ───────────────────────────────────────────────────────

ipcMain.handle("mcp:connect", async (_event, config) => {
  log.event("mcp:connect", { name: config.name, command: config.command });
  try {
    const result = await mcpClient.connectServer(config);
    log.event("mcp:connected", { name: config.name, toolCount: result.tools.length });
    return { ok: true, tools: result.tools };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("mcp:disconnect", async (_event, name) => {
  await mcpClient.disconnectServer(name);
  return { ok: true };
});

ipcMain.handle("mcp:call-tool", async (_event, serverName, toolName, args) => {
  try {
    const result = await mcpClient.callTool(serverName, toolName, args);
    return { ok: true, result };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("mcp:list-tools", () => mcpClient.getAllTools());

ipcMain.handle("mcp:list-servers", () => mcpClient.getConnectedServers());

// ── IPC: MCP Server (CursorBuddy as server) ──────────────────────

ipcMain.handle("mcp:server-start", async (_event, port) => {
  try {
    const actualPort = await mcpServer.startSSEServer(port || 6274);
    return { ok: true, port: actualPort };
  } catch (err) {
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("mcp:server-stop", async () => {
  await mcpServer.stopSSEServer();
  return { ok: true };
});

ipcMain.handle("mcp:server-status", () => mcpServer.getServerStatus());

// ── IPC: Tool Loader ─────────────────────────────────────────────────────

ipcMain.handle("tools:list", () => toolLoader.getToolList());

ipcMain.handle("tools:execute", async (_event, name, params) => {
  log.event("tool:execute", { name, params: JSON.stringify(params)?.slice(0, 200) });
  try {
    const result = await toolLoader.executeTool(name, params);
    log.event("tool:result", { name, resultLength: JSON.stringify(result)?.length });
    return { ok: true, result };
  } catch (err) {
    log.error("tool:error", err, { name });
    return { ok: false, error: err.message };
  }
});

ipcMain.handle("tools:reload", async () => {
  return toolLoader.loadAllTools();
});

// ── IPC: Session Logs ─────────────────────────────────────

ipcMain.handle("logs:current-path", () => log.getLogPath());
ipcMain.handle("logs:session-id", () => log.SESSION_ID);
ipcMain.handle("logs:list", () => {
  const logDir = log.getLogDir();
  try {
    const files = require("fs").readdirSync(logDir)
      .filter(f => f.endsWith(".jsonl"))
      .sort()
      .reverse()
      .slice(0, 20);
    return files.map(f => ({ name: f, path: require("path").join(logDir, f) }));
  } catch (_) { return []; }
});
ipcMain.handle("logs:read", (_event, filePath) => {
  try {
    const logDir = log.getLogDir();
    const resolved = require("path").resolve(filePath);
    if (!resolved.startsWith(logDir)) {
      return "Error: Access denied — path outside log directory";
    }
    return require("fs").readFileSync(filePath, "utf-8");
  } catch (err) { return `Error: ${err.message}`; }
});

// ── IPC: CLI Path Verification ────────────────────────────────

function verifyCLIPath(binaryName) {
  return new Promise((resolve) => {
    const cmd = process.platform === "win32" ? "where" : "which";
    execFile(cmd, [binaryName], (error, stdout) => {
      if (error) {
        resolve({ found: false, path: null });
      } else {
        resolve({ found: true, path: stdout.trim().split("\n")[0] });
      }
    });
  });
}

function getCLIVersion(binaryPath) {
  return new Promise((resolve) => {
    execFile(binaryPath, ["--version"], { timeout: 5000 }, (error, stdout, stderr) => {
      if (error) {
        resolve(null);
      } else {
        resolve((stdout || stderr).trim().split("\n")[0]);
      }
    });
  });
}

ipcMain.handle("verify-cli", async (_event, binaryName) => {
  const result = await verifyCLIPath(binaryName);
  if (result.found && result.path) {
    const version = await getCLIVersion(result.path);
    return { found: true, path: result.path, version };
  }
  return { found: false, path: null, version: null };
});

// ── App Lifecycle ─────────────────────────────────────────────

app.on("before-quit", () => {
  app.isQuitting = true;
  log.event("app:quit");
  log.close();
  try { mcpClient.disconnectAll(); } catch (_) {}
  try { toolLoader.stopWatching(); } catch (_) {}
});

app.whenReady().then(() => {
  if (process.platform === "darwin") app.dock.hide();

  // ── CSP Header ──────────────────────────────────────────────
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        "Content-Security-Policy": [
          "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline' https://unpkg.com; img-src 'self' data: blob:; connect-src 'self' ws: wss: http://localhost:* http://127.0.0.1:*; font-src 'self' https://unpkg.com"
        ],
      },
    });
  });

  log.event("app:ready", { platform: process.platform, isDev: !app.isPackaged });

  createTray();
  createOverlayWindow();
  startCursorTracking();
  registerPushToTalk();
  startScreenshotInterceptor();

  // Load calibration from settings
  const startupSettings = loadSettings();
  if (startupSettings.calibration) {
    setCalibration(startupSettings.calibration);
    console.log('[Calibration] Loaded:', JSON.stringify(startupSettings.calibration));
  }

  // Load pi-compatible tools and watch for changes
  toolLoader.loadAllTools().then(() => toolLoader.watchToolDirs());

  // Auto-reconnect saved MCP servers
  const savedSettings = loadSettings();
  if (savedSettings.mcpServers && Array.isArray(savedSettings.mcpServers)) {
    const reconnectPromises = savedSettings.mcpServers.map(config =>
      mcpClient.connectServer(config).then(
        (result) => console.log(`[MCP] Auto-connected: ${config.name} (${result.tools.length} tools)`),
        (err) => console.warn(`[MCP] Auto-connect failed for ${config.name}:`, err.message)
      )
    );
    Promise.all(reconnectPromises).then(() => {
      console.log(`[MCP] All servers reconnected. Total tools: ${mcpClient.getAllTools().length}`);
      sendToPanel("mcp:tools-updated", mcpClient.getAllTools().length);
    });
  }
  screen.on("display-added", broadcastScreenBounds);
  screen.on("display-removed", broadcastScreenBounds);
  screen.on("display-metrics-changed", broadcastScreenBounds);
});

// ── Screenshot Interceptor ─────────────────────────────────

let lastClipboardHash = null;

function startScreenshotInterceptor() {
  setInterval(() => {
    const img = clipboard.readImage();
    if (img.isEmpty()) return;

    // Use size as a cheap hash instead of comparing multi-MB data URLs
    const size = img.getSize();
    const hash = `${size.width}x${size.height}`;
    if (hash === lastClipboardHash) return;
    lastClipboardHash = hash;

    let thumb = img;
    if (size.width > 400) thumb = img.resize({ width: 400 });

    const thumbDataUrl = thumb.toDataURL();
    const jpegB64 = thumb.toJPEG(80).toString("base64");

    sendToPanel("screenshot:intercepted", {
      thumbnailDataUrl: thumbDataUrl,
      fullBase64: jpegB64,
      width: size.width,
      height: size.height,
    });
    sendToOverlay("overlay-command", "cursor:fly-to", {
      x: size.width / 2, y: size.height / 2,
      label: "screenshot",
      bubbleText: "screenshot captured! ask me about it",
    });
  }, 500);
}

// ── Push-to-Talk Global Shortcut ──────────────────────────
//
// Uses Electron's globalShortcut as a toggle (press to start,
// press to stop). The overlay window (always alive) handles
// mic capture so PTT works even when the panel is closed.

let isPushToTalkActive = false;
let pttFinalTranscript = "";
let registeredPTTShortcut = null;

/**
 * Convert a settings shortcut string like "Ctrl + Alt + Space"
 * to an Electron accelerator like "Ctrl+Alt+Space".
 */
function toElectronAccelerator(shortcut) {
  return shortcut
    .replace(/\s*\+\s*/g, "+")
    .replace(/Cmd/gi, "Command")
    .replace(/Option/gi, "Alt");
}

function registerPushToTalk() {
  const PTT_DEFAULT = "Ctrl+Alt+Space";
  const settings = loadSettings();
  let shortcutStr = settings.shortcut_ptt || PTT_DEFAULT;

  // Validate: must have a non-modifier key (not just "Alt+" or "Ctrl+")
  const parts = shortcutStr.replace(/\s/g, "").split("+").filter(Boolean);
  const modifierNames = new Set(["ctrl", "alt", "shift", "cmd", "command", "option", "meta", "control"]);
  const hasNonModifier = parts.some(p => !modifierNames.has(p.toLowerCase()));
  if (!hasNonModifier || parts.length < 2) {
    console.warn(`[PTT] Invalid shortcut "${shortcutStr}", falling back to ${PTT_DEFAULT}`);
    shortcutStr = PTT_DEFAULT;
  }

  const accelerator = toElectronAccelerator(shortcutStr);

  // Unregister previous shortcut if different
  if (registeredPTTShortcut && registeredPTTShortcut !== accelerator) {
    try { globalShortcut.unregister(registeredPTTShortcut); } catch (_) {}
  }

  let registered = false;
  try {
    registered = globalShortcut.register(accelerator, () => {
    if (isPushToTalkActive) {
      log.event("ptt:stop_toggle");
      stopPushToTalk();
      return;
    }

    isPushToTalkActive = true;
    pttFinalTranscript = "";
    log.event("ptt:start", { shortcut: shortcutStr });

    sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "listening" });
    // Overlay captures mic audio (always alive, unlike panel)
    sendToOverlay("push-to-talk", "start");
    sendToPanel("push-to-talk", "start");

    const currentSettings = loadSettings();
    transcription.startSession(
      currentSettings.sttProvider || "assemblyai",
      currentSettings,
      (text) => {
        pttFinalTranscript = text;
        broadcast("stt:transcript", { text, isFinal: false });
        // Show live transcript at the cursor
        sendToOverlay("overlay-command", "cursor:set-bubble-text", { text });
      },
      (text) => {
        pttFinalTranscript = text;
        broadcast("stt:transcript", { text, isFinal: true });
      },
      (err) => console.error("[STT]", err.message)
    ).catch(err => console.error("[STT] Start failed:", err.message));
  });

  } catch (err) {
    console.error(`[PTT] Failed to register shortcut "${accelerator}":`, err.message);
  }

  if (registered) {
    registeredPTTShortcut = accelerator;
    const pttLabel = process.platform === "darwin"
      ? shortcutStr.replace(/Ctrl/gi, "⌃").replace(/Alt/gi, "⌥").replace(/Shift/gi, "⇧").replace(/Cmd/gi, "⌘").replace(/\s*\+\s*/g, " ")
      : shortcutStr;
    log.event("ptt:registered", { combo: pttLabel });
    console.log(`[PTT] Global shortcut registered: ${pttLabel}`);
  } else {
    console.warn(`[PTT] Failed to register global shortcut: ${accelerator}`);
  }
}

function stopPushToTalk() {
  if (!isPushToTalkActive) return;
  isPushToTalkActive = false;
  transcription.requestFinal();
  sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "processing" });
  sendToOverlay("push-to-talk", "stop");
  sendToPanel("push-to-talk", "stop");

  // Wait for final transcript then run inference
  setTimeout(async () => {
    transcription.stopSession();
    if (pttFinalTranscript.trim()) {
      log.event("ptt:inference", { transcript: pttFinalTranscript.slice(0, 80) });
      try {
        const screens = await captureAllScreens();
        const cursorScreen = screens.find(s => s.isCursorScreen) || screens[0];
        const currentSettings = loadSettings();
        const allTools = [
          ...getSystemTools(),
          ...mcpClient.getAllTools(),
          ...toolLoader.getToolList(),
        ];
        let fullResponseText = "";
        let firstTextReceived = false;

        await runInference({
          provider: currentSettings.chatProvider || "anthropic",
          model: currentSettings.chatModel || "claude-sonnet-4-6",
          transcript: pttFinalTranscript,
          screens,
          settings: currentSettings,
          mcpTools: allTools.length > 0 ? allTools : undefined,
          onChunk: async (chunk) => {
            if (chunk.type === "text") {
              fullResponseText = chunk.text || "";
              // Switch to responding on first text chunk
              if (!firstTextReceived) {
                firstTextReceived = true;
                sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "responding" });
              }
            }
            if (chunk.type === "done") {
              if (fullResponseText) {
                const parsed = parsePointingCoordinates(fullResponseText);
                if (parsed.coordinate) {
                  const targetScreen = parsed.screenNumber
                    ? screens[Math.max(0, Math.min(parsed.screenNumber - 1, screens.length - 1))]
                    : (cursorScreen || screens[0]);
                  if (targetScreen) {
                    const sc = screenshotPointToScreenCoords(parsed.coordinate.x, parsed.coordinate.y, targetScreen);
                    chunk.scaledPoint = {
                      x: Math.round(sc.x), y: Math.round(sc.y),
                      label: parsed.elementLabel || "element",
                      bubbleText: parsed.spokenText.length > 80
                        ? parsed.spokenText.slice(0, 77).replace(/\s+\S*$/, "") + "\u2026"
                        : parsed.spokenText,
                    };
                  }
                }
              }
              // Back to idle when done
              sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "idle" });
            }
            broadcast("inference:chunk", chunk);
          },
        });
      } catch (err) {
        log.error("ptt:inference_error", err);
        broadcast("inference:chunk", { type: "error", error: err.message });
        sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "idle" });
      }
    } else {
      // No transcript — go back to idle immediately
      sendToOverlay("overlay-command", "cursor:set-voice-state", { state: "idle" });
    }
    sendToOverlay("overlay-command", "cursor:set-bubble-text", { text: "" });
  }, 2000);
}

// Toggle push-to-talk off (called from renderer)
ipcMain.on("push-to-talk:stop", () => stopPushToTalk());

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
});

app.on("window-all-closed", () => {});
