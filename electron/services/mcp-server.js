/**
 * MCP Server
 *
 * Exposes CursorBuddy as an MCP tool server.
 * Transports:
 *   - HTTP/SSE on a local port (for network agents)
 *   - stdio (for Claude Code / Codex piped connections)
 *
 * Other agents connect and can control the cursor, capture
 * screenshots, speak via TTS, etc.
 */

const http = require("http");
const crypto = require("crypto");
const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { SSEServerTransport } = require("@modelcontextprotocol/sdk/server/sse.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const { z } = require("zod");
const { captureAllScreens } = require("./capture.js");

let overlayWindow = null;
let mcpServer = null;
let httpServer = null;
let sseTransport = null;
let serverPort = null;

// Bearer token for authenticating /call requests
const authToken = crypto.randomBytes(32).toString("hex");

function isAllowedOrigin(origin) {
  if (!origin) return true; // same-origin / non-browser
  try {
    const url = new URL(origin);
    return url.hostname === "localhost" || url.hostname === "127.0.0.1";
  } catch (_) { return false; }
}

function setOverlayWindow(win) {
  overlayWindow = win;
}

function sendToOverlay(command, payload) {
  if (overlayWindow && !overlayWindow.isDestroyed()) {
    overlayWindow.webContents.send("overlay-command", command, payload);
  }
}

function createMCPServer() {
  const server = new McpServer({
    name: "cursorbuddy",
    version: "0.1.0",
  });

  // ── Tools ───────────────────────────────────────────────

  server.tool("cursor_fly_to", "Fly the cursor buddy to screen coordinates", {
    x: z.number().describe("X coordinate (logical screen pixels)"),
    y: z.number().describe("Y coordinate (logical screen pixels)"),
    label: z.string().describe("Short 1-3 word label"),
    bubbleText: z.string().optional().describe("Text shown in the cursor speech bubble"),
  }, async ({ x, y, label, bubbleText }) => {
    sendToOverlay("cursor:fly-to", { x, y, label, bubbleText });
    return { content: [{ type: "text", text: `Flying to (${x}, ${y}) — "${label}"` }] };
  });

  server.tool("cursor_fly_to_anchor", "Fly to a named viewport position", {
    position: z.string().describe("center, top-left, top-right, bottom-left, bottom-right, top-center, bottom-center, center-left, center-right"),
    label: z.string().describe("Short label"),
    bubbleText: z.string().optional().describe("Optional bubble text"),
  }, async ({ position, label, bubbleText }) => {
    sendToOverlay("cursor:fly-to-anchor", { position, label, bubbleText });
    return { content: [{ type: "text", text: `Flying to ${position}` }] };
  });

  server.tool("cursor_set_voice_state", "Set the cursor visual state", {
    state: z.string().describe("idle, listening, processing, or responding"),
  }, async ({ state }) => {
    sendToOverlay("cursor:set-voice-state", { state });
    return { content: [{ type: "text", text: `Voice state → ${state}` }] };
  });

  server.tool("cursor_show", "Show the cursor overlay", {}, async () => {
    sendToOverlay("cursor:show", {});
    return { content: [{ type: "text", text: "Cursor shown" }] };
  });

  server.tool("cursor_hide", "Hide the cursor overlay", {}, async () => {
    sendToOverlay("cursor:hide", {});
    return { content: [{ type: "text", text: "Cursor hidden" }] };
  });

  server.tool("screenshot_capture", "Capture screenshots of all displays", {}, async () => {
    try {
      const screens = await captureAllScreens();
      const summaries = screens.map(s => ({
        label: s.label, isCursorScreen: s.isCursorScreen,
        dimensions: `${s.screenshotWidthPx}x${s.screenshotHeightPx}`,
      }));
      return {
        content: [
          { type: "text", text: JSON.stringify(summaries, null, 2) },
          ...screens.map(s => ({ type: "image", data: s.imageDataBase64, mimeType: "image/jpeg" })),
        ],
      };
    } catch (err) {
      return { content: [{ type: "text", text: `Capture failed: ${err.message}` }] };
    }
  });

  server.tool("cursor_set_audio_level", "Drive the waveform visualization (0-1)", {
    level: z.number().describe("Audio level 0.0 to 1.0"),
  }, async ({ level }) => {
    sendToOverlay("voice:audio-level", { level });
    return { content: [{ type: "text", text: `Audio level → ${level}` }] };
  });

  server.tool("tts_speak", "Speak text aloud via configured TTS", {
    text: z.string().describe("Text to speak"),
  }, async ({ text }) => {
    // TTS is handled by the main process — we relay via overlay command
    sendToOverlay("tts:speak-request", { text });
    return { content: [{ type: "text", text: `Speaking: "${text.slice(0, 50)}..."` }] };
  });

  mcpServer = server;
  return server;
}

// ── HTTP/SSE Transport ────────────────────────────────────

async function startSSEServer(port) {
  await stopSSEServer();

  const server = mcpServer || createMCPServer();

  httpServer = http.createServer(async (req, res) => {
    // CORS headers for cross-origin MCP clients
    const origin = req.headers.origin || "";
    if (isAllowedOrigin(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin || "http://localhost");
    }
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.writeHead(200);
      res.end();
      return;
    }

    if (req.url === "/sse" && req.method === "GET") {
      // SSE connection — create fresh server for each connection
      // (McpServer.connect can only be called once per instance)
      if (sseTransport) {
        console.log("[MCP SSE] Client reconnecting");
        try { await sseTransport.close(); } catch (_) {}
        sseTransport = null;
      }
      // Always create a fresh MCP server for the new SSE session
      const freshServer = createMCPServer();
      sseTransport = new SSEServerTransport("/messages", res);
      await freshServer.connect(sseTransport);
      console.log("[MCP SSE] Client connected");
      return;
    }

    if (req.url === "/messages" && req.method === "POST") {
      if (!sseTransport) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "No SSE connection. Connect to /sse first." }));
        return;
      }
      await sseTransport.handlePostMessage(req, res);
      return;
    }

    // Direct tool call endpoint (for CLI — doesn't need SSE session)
    if (req.url === "/call" && req.method === "POST") {
      // Authenticate /call requests with bearer token
      const authHeader = req.headers.authorization || "";
      if (authHeader !== `Bearer ${authToken}`) {
        res.writeHead(401, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Unauthorized — invalid or missing bearer token" }));
        return;
      }
      let body = "";
      req.on("data", (chunk) => (body += chunk));
      req.on("end", async () => {
        try {
          const { tool, args } = JSON.parse(body);
          if (!tool) {
            res.writeHead(400, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: "Missing 'tool' field" }));
            return;
          }
          // Find the tool handler and call it directly
          const knownTools = {
              cursor_fly_to: () => { sendToOverlay("cursor:fly-to", args); return { text: `Flying to (${args.x}, ${args.y})` }; },
              cursor_fly_to_anchor: () => { sendToOverlay("cursor:fly-to-anchor", args); return { text: `Flying to ${args.position}` }; },
              cursor_set_voice_state: () => { sendToOverlay("cursor:set-voice-state", args); return { text: `State → ${args.state}` }; },
              cursor_show: () => { sendToOverlay("cursor:show", {}); return { text: "Shown" }; },
              cursor_hide: () => { sendToOverlay("cursor:hide", {}); return { text: "Hidden" }; },
              cursor_set_audio_level: () => { sendToOverlay("voice:audio-level", args); return { text: `Level → ${args.level}` }; },
              tts_speak: () => { sendToOverlay("tts:speak-request", args); return { text: `Speaking: ${(args.text || "").slice(0, 50)}` }; },
              screenshot_capture: async () => { const s = await captureAllScreens(); return { text: `${s.length} screen(s) captured`, screens: s.length }; },
            };
          const handler = knownTools[tool];
          if (handler) {
            const result = await handler();
            res.writeHead(200, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ ok: true, result }));
          } else {
            res.writeHead(404, { "Content-Type": "application/json" });
            res.end(JSON.stringify({ error: `Unknown tool: ${tool}` }));
          }
          return;
        } catch (err) {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: err.message }));
        }
      });
      return;
    }

    // Info endpoint
    if (req.url === "/" || req.url === "/info") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        name: "cursorbuddy",
        version: "0.1.0",
        transport: "sse",
        endpoints: { sse: "/sse", messages: "/messages" },
        tools: [
          "cursor_fly_to", "cursor_fly_to_anchor", "cursor_set_voice_state",
          "cursor_show", "cursor_hide", "screenshot_capture",
          "cursor_set_audio_level", "tts_speak",
        ],
      }));
      return;
    }

    res.writeHead(404);
    res.end("Not found");
  });

  return new Promise((resolve, reject) => {
    httpServer.listen(port || 0, "127.0.0.1", () => {
      serverPort = httpServer.address().port;
      console.log(`[MCP SSE] Server listening on http://127.0.0.1:${serverPort}`);
      resolve(serverPort);
    });
    httpServer.on("error", reject);
  });
}

async function stopSSEServer() {
  if (sseTransport) {
    try { await sseTransport.close(); } catch (_) {}
    sseTransport = null;
  }
  if (httpServer) {
    return new Promise((resolve) => {
      httpServer.close(() => {
        httpServer = null;
        serverPort = null;
        console.log("[MCP SSE] Server stopped");
        resolve();
      });
    });
  }
}

function getServerStatus() {
  return {
    running: !!httpServer,
    port: serverPort,
    url: serverPort ? `http://127.0.0.1:${serverPort}` : null,
    sseUrl: serverPort ? `http://127.0.0.1:${serverPort}/sse` : null,
    hasClient: !!sseTransport,
  };
}

// ── stdio Transport ───────────────────────────────────────

async function startStdioTransport() {
  const server = mcpServer || createMCPServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.log("[MCP] Server running on stdio");
}

module.exports = { createMCPServer, startSSEServer, stopSSEServer, getServerStatus, startStdioTransport, setOverlayWindow, authToken };
