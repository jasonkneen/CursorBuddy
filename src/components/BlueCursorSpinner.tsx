/**
 * Blue Cursor Spinner
 *
 * Spinning arc indicator shown while AI is processing.
 * Renders at a fixed local position within the OverlayViewport.
 */

import React from "react";
import { useCursorStore } from "../stores/cursor-store";
import { DS } from "../lib/design-tokens";
import { runtimeConfig } from "../lib/runtime-config";
import { useRuntimeConfig } from "../hooks/use-runtime-config";

export const BlueCursorSpinner: React.FC = () => {
  const voiceState = useCursorStore((s) => s.voiceState);
  const cursorOpacity = useCursorStore((s) => s.cursorOpacity);

  useRuntimeConfig();
  const color = runtimeConfig.cursorColor;
  const isVisible = voiceState === "processing";

  // Fixed local position — centered on localBuddy
  const localX = DS.viewport.localBuddyX;
  const localY = DS.viewport.localBuddyY;

  return (
    <div
      style={{
        position: "absolute",
        left: localX - 7,
        top: localY - 7,
        opacity: isVisible ? cursorOpacity : 0,
        transition: "opacity 0.15s ease",
        willChange: "opacity",
        pointerEvents: "none",
        filter: `drop-shadow(0 0 6px ${color}99)`,
      }}
    >
      <svg
        width="14"
        height="14"
        viewBox="0 0 14 14"
        style={{ animation: "clicky-spin 0.8s linear infinite" }}
      >
        <circle
          cx="7"
          cy="7"
          r="5.5"
          fill="none"
          stroke={color}
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeDasharray="24.2 10.4"
        />
      </svg>
    </div>
  );
};
