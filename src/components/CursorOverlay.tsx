/**
 * Cursor Overlay
 *
 * Root component for the compact buddy overlay. Wraps all visuals
 * in an OverlayViewport that moves to follow the cursor.
 *
 * The viewport is a small transparent popover (320×80). Child
 * components render at fixed local positions within it. The viewport
 * itself moves via Tauri window.setPosition() or CSS transforms.
 *
 * External systems drive it through the event bus:
 *   - "cursor:fly-to" → flight to a screen element
 *   - "cursor:set-voice-state" → triangle/waveform/spinner
 *   - "voice:audio-level" → waveform reactivity
 *   - "cursor:show" / "cursor:hide" → visibility
 */

import React, { useEffect } from "react";
import { useCursorTracking } from "../hooks/use-cursor-tracking";
import { useBuddyNavigation } from "../hooks/use-buddy-navigation";
import { useElectronBridge } from "../hooks/use-electron-bridge";
import { useCursorStore } from "../stores/cursor-store";
import { eventBus } from "../events/event-bus";
import { OverlayViewport } from "./OverlayViewport";
import { BlueCursorTriangle } from "./BlueCursorTriangle";
import { BlueCursorWaveform } from "./BlueCursorWaveform";
import { BlueCursorSpinner } from "./BlueCursorSpinner";
import { NavigationBubble } from "./NavigationBubble";

export const CursorOverlay: React.FC = () => {
  useCursorTracking();
  useBuddyNavigation();
  useElectronBridge();

  const isOverlayVisible = useCursorStore((s) => s.isOverlayVisible);
  const setVoiceState = useCursorStore((s) => s.setVoiceState);
  const setAudioLevel = useCursorStore((s) => s.setAudioLevel);
  const setIsOverlayVisible = useCursorStore((s) => s.setIsOverlayVisible);
  const setNavigationBubbleText = useCursorStore((s) => s.setNavigationBubbleText);
  const setNavigationBubbleOpacity = useCursorStore((s) => s.setNavigationBubbleOpacity);
  const setNavigationBubbleScale = useCursorStore((s) => s.setNavigationBubbleScale);

  // ── Wire event bus to store ─────────────────────────────────
  useEffect(() => {
    const handleVoiceState = (payload: {
      state: "idle" | "listening" | "processing" | "responding";
    }) => {
      setVoiceState(payload.state);
    };

    const handleAudioLevel = (payload: { level: number }) => {
      setAudioLevel(payload.level);
    };

    const handleShow = () => setIsOverlayVisible(true);
    const handleHide = () => setIsOverlayVisible(false);

    const handleBubbleText = (payload: { text: string }) => {
      if (payload.text) {
        setNavigationBubbleText(payload.text);
        setNavigationBubbleOpacity(1.0);
        setNavigationBubbleScale(1.0);
      } else {
        setNavigationBubbleOpacity(0);
        setNavigationBubbleScale(0.5);
        setTimeout(() => setNavigationBubbleText(""), 200);
      }
    };

    eventBus.on("cursor:set-voice-state", handleVoiceState);
    eventBus.on("voice:audio-level", handleAudioLevel);
    eventBus.on("cursor:show", handleShow);
    eventBus.on("cursor:hide", handleHide);
    eventBus.on("cursor:set-bubble-text", handleBubbleText);

    return () => {
      eventBus.off("cursor:set-voice-state", handleVoiceState);
      eventBus.off("voice:audio-level", handleAudioLevel);
      eventBus.off("cursor:show", handleShow);
      eventBus.off("cursor:hide", handleHide);
      eventBus.off("cursor:set-bubble-text", handleBubbleText);
    };
  }, [setVoiceState, setAudioLevel, setIsOverlayVisible, setNavigationBubbleText, setNavigationBubbleOpacity, setNavigationBubbleScale]);

  if (!isOverlayVisible) return null;

  return (
    <OverlayViewport>
      {/* All three visual states stay mounted and cross-fade via opacity
          so React doesn't unmount/remount them (which causes a visible pop) */}
      <BlueCursorTriangle />
      <BlueCursorWaveform />
      <BlueCursorSpinner />
      <NavigationBubble />
    </OverlayViewport>
  );
};
