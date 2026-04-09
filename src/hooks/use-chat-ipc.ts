/**
 * Chat IPC Hook
 *
 * Encapsulates all direct window.electronAPI access for the chat panel:
 *   - Inference chunk streaming (onInferenceChunk)
 *   - Speech-to-text transcripts (onTranscript)
 *   - Triggering inference (runInference)
 *   - Text-to-speech (speak)
 *
 * ChatPanel uses this hook instead of touching electronAPI directly.
 */

import { useEffect, useCallback } from "react";
import { isElectronEnvironment } from "../lib/is-electron";

// ── Types ─────────────────────────────────────────────────────

export interface InferenceChunk {
  type: "thinking" | "text" | "done" | "error";
  text?: string;
  error?: string;
}

export interface TranscriptData {
  text: string;
  isFinal: boolean;
}

export interface SpeakResult {
  ok: boolean;
  audioBase64?: string;
  mimeType?: string;
}

interface UseChatIPCOptions {
  /** Called for each inference chunk from the main process */
  onInferenceChunk: (chunk: InferenceChunk) => void;
  /** Called when a speech-to-text transcript arrives */
  onTranscript: (data: TranscriptData) => void;
}

interface UseChatIPCReturn {
  /** Trigger an inference run via Electron IPC */
  runInference: (params: { transcript: string }) => void;
  /** Request TTS via Electron IPC. Returns null if not available. */
  speak: (text: string) => Promise<SpeakResult | null>;
}

export function useChatIPC(options: UseChatIPCOptions): UseChatIPCReturn {
  // ── Listen for inference chunks ───────────────────────────
  useEffect(() => {
    if (!isElectronEnvironment() || !window.electronAPI?.onInferenceChunk) return;

    const unsubscribe = window.electronAPI.onInferenceChunk(
      (chunk: { type: string; text?: string; error?: string }) => {
        options.onInferenceChunk(chunk as InferenceChunk);
      }
    );
    return () => {
      unsubscribe();
    };
  }, [options.onInferenceChunk]);

  // ── Listen for STT transcripts ────────────────────────────
  useEffect(() => {
    if (!isElectronEnvironment() || !window.electronAPI?.onTranscript) return;

    const unsubscribe = window.electronAPI.onTranscript(options.onTranscript);
    return () => {
      unsubscribe();
    };
  }, [options.onTranscript]);

  // ── Outgoing IPC calls ────────────────────────────────────

  const runInference = useCallback((params: { transcript: string }) => {
    if (isElectronEnvironment()) {
      window.electronAPI?.runInference?.(params);
    }
  }, []);

  const speak = useCallback(async (text: string): Promise<SpeakResult | null> => {
    if (!isElectronEnvironment() || !window.electronAPI?.speak) return null;
    return window.electronAPI.speak(text);
  }, []);

  return { runInference, speak };
}
