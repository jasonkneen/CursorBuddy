/**
 * Cursor Overlay Store
 *
 * Manages all state for the blue cursor companion: position, navigation
 * mode, voice state, animation parameters, and speech bubble content.
 *
 * The store is the single source of truth for the overlay renderer.
 * External systems drive it through the event bus; the React components
 * read from it via Zustand selectors.
 */

import { create } from "zustand";
import { DS } from "../lib/design-tokens";

export type VoiceState = "idle" | "listening" | "processing" | "responding";

export type BuddyNavigationMode =
  | "following-cursor"
  | "navigating-to-target"
  | "pointing-at-target";

export interface CursorPosition {
  x: number;
  y: number;
}

export interface FlyToTarget {
  x: number;
  y: number;
  label: string;
  bubbleText?: string;
}

interface CursorStoreState {
  // ── Position ──────────────────────────────────────────────
  /** The buddy's current rendered position (screen-local px) */
  buddyPosition: CursorPosition;
  /** The system cursor's current position (screen-local px) */
  systemCursorPosition: CursorPosition;

  // ── Navigation ────────────────────────────────────────────
  navigationMode: BuddyNavigationMode;
  flyToTarget: FlyToTarget | null;
  /** True when the buddy is flying BACK to cursor after pointing */
  isReturningToCursor: boolean;
  /** Cursor position when navigation started (for cancel detection) */
  cursorPositionAtNavigationStart: CursorPosition | null;

  // ── Voice state ───────────────────────────────────────────
  voiceState: VoiceState;
  /** Live audio power level 0–1 for waveform bars */
  audioLevel: number;

  // ── Animation ─────────────────────────────────────────────
  /** Triangle rotation in degrees (-35° default, changes during flight) */
  triangleRotationDegrees: number;
  /** Scale factor during flight (1.0 default, peaks at 1.3 mid-arc) */
  buddyFlightScale: number;

  // ── Speech bubble ─────────────────────────────────────────
  /** Text currently shown in the navigation speech bubble */
  navigationBubbleText: string;
  navigationBubbleOpacity: number;
  navigationBubbleScale: number;

  // ── Visibility ────────────────────────────────────────────
  isOverlayVisible: boolean;
  cursorOpacity: number;

  // ── Actions ───────────────────────────────────────────────
  setBuddyPosition: (position: CursorPosition) => void;
  setSystemCursorPosition: (position: CursorPosition) => void;
  setNavigationMode: (mode: BuddyNavigationMode) => void;
  setFlyToTarget: (target: FlyToTarget | null) => void;
  setIsReturningToCursor: (returning: boolean) => void;
  setCursorPositionAtNavigationStart: (position: CursorPosition | null) => void;
  setVoiceState: (state: VoiceState) => void;
  setAudioLevel: (level: number) => void;
  setTriangleRotationDegrees: (degrees: number) => void;
  setBuddyFlightScale: (scale: number) => void;
  setNavigationBubbleText: (text: string) => void;
  setNavigationBubbleOpacity: (opacity: number) => void;
  setNavigationBubbleScale: (scale: number) => void;
  setIsOverlayVisible: (visible: boolean) => void;
  setCursorOpacity: (opacity: number) => void;
  /** Reset navigation state back to cursor-following */
  resetToFollowingCursor: () => void;
}

export const useCursorStore = create<CursorStoreState>((set) => ({
  // ── Initial state ─────────────────────────────────────────
  buddyPosition: { x: 0, y: 0 },
  systemCursorPosition: { x: 0, y: 0 },
  navigationMode: "following-cursor",
  flyToTarget: null,
  isReturningToCursor: false,
  cursorPositionAtNavigationStart: null,
  voiceState: "idle",
  audioLevel: 0,
  triangleRotationDegrees: DS.defaultTriangleRotation,
  buddyFlightScale: 1.0,
  navigationBubbleText: "",
  navigationBubbleOpacity: 0,
  navigationBubbleScale: 1.0,
  isOverlayVisible: true,
  cursorOpacity: 1.0,

  // ── Setters ───────────────────────────────────────────────
  setBuddyPosition: (position) => set({ buddyPosition: position }),
  setSystemCursorPosition: (position) => set({ systemCursorPosition: position }),
  setNavigationMode: (mode) => set({ navigationMode: mode }),
  setFlyToTarget: (target) => set({ flyToTarget: target }),
  setIsReturningToCursor: (returning) => set({ isReturningToCursor: returning }),
  setCursorPositionAtNavigationStart: (position) =>
    set({ cursorPositionAtNavigationStart: position }),
  setVoiceState: (state) => set({ voiceState: state }),
  setAudioLevel: (level) => set({ audioLevel: level }),
  setTriangleRotationDegrees: (degrees) => set({ triangleRotationDegrees: degrees }),
  setBuddyFlightScale: (scale) => set({ buddyFlightScale: scale }),
  setNavigationBubbleText: (text) => set({ navigationBubbleText: text }),
  setNavigationBubbleOpacity: (opacity) => set({ navigationBubbleOpacity: opacity }),
  setNavigationBubbleScale: (scale) => set({ navigationBubbleScale: scale }),
  setIsOverlayVisible: (visible) => set({ isOverlayVisible: visible }),
  setCursorOpacity: (opacity) => set({ cursorOpacity: opacity }),

  resetToFollowingCursor: () =>
    set({
      navigationMode: "following-cursor",
      flyToTarget: null,
      isReturningToCursor: false,
      cursorPositionAtNavigationStart: null,
      triangleRotationDegrees: DS.defaultTriangleRotation,
      buddyFlightScale: 1.0,
      navigationBubbleText: "",
      navigationBubbleOpacity: 0,
      navigationBubbleScale: 1.0,
    }),
}));
