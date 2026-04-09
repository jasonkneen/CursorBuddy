/**
 * Electron Bridge Hook
 *
 * Encapsulates all direct window.electronAPI access for the overlay:
 *   - Relays overlay commands from the main process to the event bus
 *   - Syncs screen bounds from main process display info
 *   - Handles push-to-talk mic capture and PCM16 streaming
 *
 * CursorOverlay calls this hook instead of touching electronAPI directly.
 */

import { useEffect } from "react";
import { eventBus } from "../events/event-bus";
import type { EventName } from "../events/event-bus";
import { setScreenBounds } from "../lib/viewport-bounds";
import { isElectronEnvironment } from "../lib/is-electron";

export function useElectronBridge(): void {
  // ── Relay panel commands to event bus (Electron only) ───────
  useEffect(() => {
    if (!isElectronEnvironment() || !window.electronAPI?.onOverlayCommand) return;

    const unsubscribe = window.electronAPI.onOverlayCommand(
      (command: string, payload: Record<string, unknown>) => {
        eventBus.emitDynamic(command, payload);
      }
    );

    return unsubscribe;
  }, []);

  // ── Sync screen bounds from Electron main process ──────────
  useEffect(() => {
    if (!isElectronEnvironment() || !window.electronAPI) return;

    // Get initial bounds
    window.electronAPI.getScreenBounds().then(setScreenBounds);

    // Listen for display changes
    const unsubscribe = window.electronAPI.onScreenBounds(setScreenBounds);
    return unsubscribe;
  }, []);

  // ── Push-to-Talk mic capture (overlay is always alive) ────
  // When PTT starts, capture mic audio and send PCM16 to main
  // process for STT. This works even when the panel is closed.
  useEffect(() => {
    if (!isElectronEnvironment() || !window.electronAPI?.onPushToTalk) return;

    let audioContext: AudioContext | null = null;
    let mediaStream: MediaStream | null = null;
    let scriptProcessor: ScriptProcessorNode | null = null;

    const startMicCapture = async () => {
      try {
        mediaStream = await navigator.mediaDevices.getUserMedia({
          audio: { channelCount: 1, sampleRate: 16000 },
        });
        audioContext = new AudioContext({ sampleRate: 16000 });
        const source = audioContext.createMediaStreamSource(mediaStream);
        // ScriptProcessorNode for PCM16 extraction + audio level
        scriptProcessor = audioContext.createScriptProcessor(4096, 1, 1);
        scriptProcessor.onaudioprocess = (event) => {
          const float32 = event.inputBuffer.getChannelData(0);
          // Convert Float32 → Int16 PCM
          const pcm16 = new Int16Array(float32.length);
          let sum = 0;
          for (let i = 0; i < float32.length; i++) {
            const s = Math.max(-1, Math.min(1, float32[i]));
            pcm16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
            sum += float32[i] * float32[i];
          }
          window.electronAPI!.sendAudio(pcm16.buffer);
          // Drive the waveform visualization directly via event bus
          const rms = Math.sqrt(sum / float32.length);
          const level = Math.min(Math.max(rms * 10, 0), 1);
          eventBus.emit("voice:audio-level", { level });
        };
        source.connect(scriptProcessor);
        scriptProcessor.connect(audioContext.destination);
      } catch (err) {
        console.error("[PTT Overlay] Mic capture failed:", err);
      }
    };

    const stopMicCapture = () => {
      if (scriptProcessor) {
        scriptProcessor.disconnect();
        scriptProcessor = null;
      }
      if (audioContext) {
        audioContext.close().catch(() => {});
        audioContext = null;
      }
      if (mediaStream) {
        mediaStream.getTracks().forEach((t) => t.stop());
        mediaStream = null;
      }
      eventBus.emit("voice:audio-level", { level: 0 });
    };

    const unsubscribe = window.electronAPI.onPushToTalk((action: string) => {
      if (action === "start") {
        startMicCapture();
      } else if (action === "stop") {
        stopMicCapture();
      }
    });

    return () => {
      unsubscribe();
      stopMicCapture();
    };
  }, []);
}
