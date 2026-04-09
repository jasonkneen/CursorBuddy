/**
 * CursorBuddy Event Bus
 *
 * Central event system connecting all components. Each subsystem
 * (cursor, voice, AI, TTS, capture) communicates exclusively through
 * events so components can be swapped, run remotely, or replaced
 * without changing the rest of the pipeline.
 *
 * The bus supports both local EventEmitter dispatch and future
 * WebSocket/SSE bridging for remote components.
 */

import EventEmitter from "eventemitter3";

// ─── Event Type Definitions ─────────────────────────────────────

/** Voice pipeline events */
export interface VoiceEvents {
  /** Push-to-talk key pressed — start recording */
  "voice:push-start": void;
  /** Push-to-talk key released — stop recording */
  "voice:push-stop": void;
  /** Live audio power level (0–1) for waveform visualization */
  "voice:audio-level": { level: number };
  /** Partial transcript update (while still recording) */
  "voice:transcript-partial": { text: string };
  /** Final transcript ready after key release */
  "voice:transcript-final": { text: string };
  /** Voice pipeline error */
  "voice:error": { message: string };
}

/** Screen capture events */
export interface CaptureEvents {
  /** Request a screenshot of all displays */
  "capture:request": void;
  /** Screenshot data ready */
  "capture:ready": {
    screens: Array<{
      imageDataBase64: string;
      label: string;
      isCursorScreen: boolean;
      displayWidthPx: number;
      displayHeightPx: number;
      screenshotWidthPx: number;
      screenshotHeightPx: number;
      displayFrame: { x: number; y: number; width: number; height: number };
    }>;
  };
  /** Capture error */
  "capture:error": { message: string };
}

/** AI inference events */
export interface InferenceEvents {
  /** Send transcript + screenshots to the AI */
  "inference:request": {
    transcript: string;
    screens: CaptureEvents["capture:ready"]["screens"];
  };
  /** Streaming text chunk from the AI */
  "inference:text-chunk": { accumulatedText: string };
  /** AI response complete — includes parsed point data */
  "inference:complete": {
    spokenText: string;
    point: {
      x: number;
      y: number;
      label: string;
      screenNumber?: number;
    } | null;
  };
  /** AI inference error */
  "inference:error": { message: string };
}

/** TTS events */
export interface TTSEvents {
  /** Request TTS playback */
  "tts:request": { text: string };
  /** TTS audio started playing */
  "tts:playing": void;
  /** TTS audio finished playing */
  "tts:finished": void;
  /** TTS error */
  "tts:error": { message: string };
}

/** Cursor overlay events */
export interface CursorEvents {
  /** System cursor position update (screen coordinates) */
  "cursor:position": { x: number; y: number };
  /** Navigate the buddy to a screen element */
  "cursor:fly-to": {
    x: number;
    y: number;
    label: string;
    bubbleText?: string;
  };
  /** Buddy arrived at the target element */
  "cursor:arrived": void;
  /** Buddy finished pointing and returned to cursor */
  "cursor:returned": void;
  /** Show/hide the cursor overlay */
  "cursor:show": void;
  "cursor:hide": void;
  /** Set the voice state (controls which visual to show) */
  "cursor:set-voice-state": {
    state: "idle" | "listening" | "processing" | "responding";
  };
  /** Set the navigation bubble text directly (e.g. live transcript) */
  "cursor:set-bubble-text": {
    text: string;
  };
}

/** Pipeline orchestration events */
export interface PipelineEvents {
  /** Full pipeline state transition */
  "pipeline:state-change": {
    from: string;
    to: string;
  };
}

/** Runtime configuration events */
export interface ConfigEvents {
  /** Settings panel pushed updated config values */
  "config:update": Record<string, unknown>;
}

/** Element selection events */
export interface SelectionEvents {
  /** Start click-drag element selection mode */
  "selection:start": void;
  /** Selection completed — returns the selected region's bounds and captured HTML */
  "selection:complete": {
    bounds: { x: number; y: number; width: number; height: number };
    html: string;
    elementCount: number;
  };
  /** Selection cancelled */
  "selection:cancel": void;
}

/** Union of all event maps */
export type AllEvents = VoiceEvents &
  CaptureEvents &
  InferenceEvents &
  TTSEvents &
  CursorEvents &
  PipelineEvents &
  ConfigEvents &
  SelectionEvents;

/** Typed event names */
export type EventName = keyof AllEvents;

// ─── Typed Event Bus ────────────────────────────────────────────

class ClickyEventBus {
  private emitter = new EventEmitter();

  /** Emit a typed event */
  emit<K extends EventName>(
    event: K,
    ...args: AllEvents[K] extends void ? [] : [AllEvents[K]]
  ): void {
    this.emitter.emit(event, ...args);
  }

  /** Listen for a typed event */
  on<K extends EventName>(
    event: K,
    handler: AllEvents[K] extends void ? () => void : (payload: AllEvents[K]) => void
  ): void {
    this.emitter.on(event, handler as (...args: unknown[]) => void);
  }

  /** Listen for a typed event once */
  once<K extends EventName>(
    event: K,
    handler: AllEvents[K] extends void ? () => void : (payload: AllEvents[K]) => void
  ): void {
    this.emitter.once(event, handler as (...args: unknown[]) => void);
  }

  /** Remove a specific listener */
  off<K extends EventName>(
    event: K,
    handler: AllEvents[K] extends void ? () => void : (payload: AllEvents[K]) => void
  ): void {
    this.emitter.off(event, handler as (...args: unknown[]) => void);
  }

  /** Remove all listeners for an event, or all events */
  removeAllListeners(event?: EventName): void {
    this.emitter.removeAllListeners(event);
  }

  // ── Dynamic (untyped) variants for runtime-determined event names ──

  /** Emit an event whose name is only known at runtime (e.g. IPC relay) */
  emitDynamic(event: string, payload?: unknown): void {
    this.emitter.emit(event, payload);
  }

  /** Listen for an event whose name is only known at runtime */
  onDynamic(event: string, handler: (...args: unknown[]) => void): void {
    this.emitter.on(event, handler);
  }

  /** Remove a dynamically-registered listener */
  offDynamic(event: string, handler: (...args: unknown[]) => void): void {
    this.emitter.off(event, handler);
  }
}

/**
 * Singleton event bus. Every component imports this same instance.
 *
 * To bridge to a remote process (e.g. WebSocket to a capture server),
 * wrap the bus with a transport adapter that forwards events over the
 * wire — the component API stays identical.
 */
export const eventBus = new ClickyEventBus();
