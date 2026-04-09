/**
 * Settings Cache
 *
 * Wraps settings read/write with a simple in-memory cache.
 * Avoids re-reading the JSON file from disk on every inference,
 * STT, and TTS call (was called 4+ times per voice interaction).
 *
 * API key fields are encrypted at rest using Electron's safeStorage.
 * Migration: plaintext keys are auto-encrypted on first save.
 *
 * Cache is invalidated on save and stale after 5 seconds.
 */

const fs = require("fs");
const path = require("path");

let safeStorage = null;
try {
  safeStorage = require("electron").safeStorage;
} catch (_) {
  // Running outside Electron (tests, CLI) — encryption unavailable
}

const SETTINGS_DIR = path.join(
  process.env.HOME || process.env.USERPROFILE || ".",
  ".cursorbuddy"
);
const SETTINGS_FILE = path.join(SETTINGS_DIR, "settings.json");

// Fields that contain API keys / secrets
const SECRET_FIELDS = [
  "anthropicApiKey",
  "openaiApiKey",
  "elevenLabsApiKey",
  "assemblyAiApiKey",
];

const ENCRYPTED_PREFIX = "enc:";

function canEncrypt() {
  return safeStorage && typeof safeStorage.isEncryptionAvailable === "function" && safeStorage.isEncryptionAvailable();
}

function encryptValue(plaintext) {
  if (!canEncrypt() || !plaintext) return plaintext;
  try {
    const buf = safeStorage.encryptString(plaintext);
    return ENCRYPTED_PREFIX + buf.toString("base64");
  } catch (err) {
    console.warn("[Settings] Encryption failed:", err.message);
    return plaintext;
  }
}

function decryptValue(stored) {
  if (!stored || !stored.startsWith(ENCRYPTED_PREFIX)) return stored; // plaintext or empty
  if (!canEncrypt()) return stored; // can't decrypt — return raw
  try {
    const buf = Buffer.from(stored.slice(ENCRYPTED_PREFIX.length), "base64");
    return safeStorage.decryptString(buf);
  } catch (err) {
    console.warn("[Settings] Decryption failed:", err.message);
    return stored;
  }
}

/** Decrypt secret fields in a settings object (returns new object) */
function decryptSecrets(settings) {
  if (!settings) return settings;
  const out = { ...settings };
  for (const field of SECRET_FIELDS) {
    if (out[field]) out[field] = decryptValue(out[field]);
  }
  return out;
}

/** Encrypt secret fields in a settings object (returns new object for disk) */
function encryptSecrets(settings) {
  if (!settings) return settings;
  const out = { ...settings };
  for (const field of SECRET_FIELDS) {
    if (out[field] && !out[field].startsWith(ENCRYPTED_PREFIX)) {
      out[field] = encryptValue(out[field]);
    }
  }
  return out;
}

/** @type {object | null} */
let cached = null;
let cacheTimestamp = 0;
const CACHE_TTL_MS = 5000;

function loadSettings() {
  const now = Date.now();
  if (cached && now - cacheTimestamp < CACHE_TTL_MS) {
    return cached;
  }
  try {
    if (fs.existsSync(SETTINGS_FILE)) {
      const raw = JSON.parse(fs.readFileSync(SETTINGS_FILE, "utf-8"));
      // Check if any secret fields need migration (plaintext → encrypted)
      let needsResave = false;
      if (canEncrypt()) {
        for (const field of SECRET_FIELDS) {
          if (raw[field] && !raw[field].startsWith(ENCRYPTED_PREFIX)) {
            needsResave = true;
            break;
          }
        }
      }
      cached = decryptSecrets(raw);
      cacheTimestamp = now;
      // Auto-migrate plaintext secrets to encrypted on disk
      if (needsResave) {
        try {
          const encrypted = encryptSecrets(cached);
          fs.writeFileSync(SETTINGS_FILE, JSON.stringify(encrypted, null, 2));
        } catch (_) {}
      }
      return cached;
    }
  } catch (err) {
    console.warn("[Settings] Failed to parse settings file:", err.message);
  }
  return {};
}

function saveSettings(settings) {
  try {
    fs.mkdirSync(SETTINGS_DIR, { recursive: true });
    const forDisk = encryptSecrets(settings);
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(forDisk, null, 2));
    // Cache the decrypted version in memory
    cached = decryptSecrets(settings);
    cacheTimestamp = Date.now();
  } catch (err) {
    console.error("[Settings] Save failed:", err.message);
  }
}

/** Force-invalidate the cache (e.g. after external edit) */
function invalidateCache() {
  cached = null;
  cacheTimestamp = 0;
}

module.exports = { loadSettings, saveSettings, invalidateCache, SETTINGS_DIR, SETTINGS_FILE };
