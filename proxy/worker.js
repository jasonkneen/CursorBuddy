/**
 * Pucks Proxy — Cloudflare Worker
 *
 * Routes:
 *   POST /chat  → Claude Messages API (streaming SSE)
 *   POST /tts   → ElevenLabs Text-to-Speech API
 *
 * Environment variables (set in Cloudflare dashboard):
 *   ANTHROPIC_API_KEY    — Anthropic API key
 *   ELEVENLABS_API_KEY   — ElevenLabs API key
 *   ELEVENLABS_VOICE_ID  — ElevenLabs voice ID (optional, defaults to a preset)
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: corsHeaders(),
      });
    }

    if (request.method !== "POST") {
      return jsonError("Method not allowed", 405);
    }

    try {
      switch (url.pathname) {
        case "/chat":
          return await handleChat(request, env);
        case "/tts":
          return await handleTTS(request, env);
        default:
          return jsonError("Not found", 404);
      }
    } catch (err) {
      console.error("Worker error:", err);
      return jsonError(err.message || "Internal error", 500);
    }
  },
};

// ─── /chat → Claude Messages API (streaming) ────────────────────────

async function handleChat(request, env) {
  const body = await request.json();

  const anthropicResponse = await fetch(
    "https://api.anthropic.com/v1/messages",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: body.model || "claude-sonnet-4-6",
        max_tokens: body.max_tokens || 4096,
        system: body.system || "",
        messages: body.messages || [],
        stream: true,
      }),
    }
  );

  if (!anthropicResponse.ok) {
    const errText = await anthropicResponse.text();
    console.error("Claude API error:", anthropicResponse.status, errText);
    return new Response(errText, {
      status: anthropicResponse.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": "application/json",
      },
    });
  }

  // Stream SSE through to client
  return new Response(anthropicResponse.body, {
    status: 200,
    headers: {
      ...corsHeaders(),
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}

// ─── /tts → ElevenLabs Text-to-Speech ────────────────────────────────

async function handleTTS(request, env) {
  const body = await request.json();
  const text = body.text || "";
  const modelId = body.model_id || "eleven_flash_v2_5";
  const voiceId = env.ELEVENLABS_VOICE_ID || "21m00Tcm4TlvDq8ikWAM"; // Rachel default

  const elevenResponse = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "xi-api-key": env.ELEVENLABS_API_KEY,
        Accept: "audio/mpeg",
      },
      body: JSON.stringify({
        text,
        model_id: modelId,
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
        },
      }),
    }
  );

  if (!elevenResponse.ok) {
    const errText = await elevenResponse.text();
    console.error("ElevenLabs error:", elevenResponse.status, errText);

    // Check for quota exceeded
    if (elevenResponse.status === 429 || elevenResponse.status === 402) {
      return jsonError(
        "I'm all out of credits. Please DM Farza and tell him to bring me back to life.",
        402
      );
    }
    return new Response(errText, {
      status: elevenResponse.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": "application/json",
      },
    });
  }

  return new Response(elevenResponse.body, {
    status: 200,
    headers: {
      ...corsHeaders(),
      "Content-Type": "audio/mpeg",
    },
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function jsonError(message, status) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: {
      ...corsHeaders(),
      "Content-Type": "application/json",
    },
  });
}
