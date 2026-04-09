/**
 * Navigation Speech Bubble
 *
 * Shown when the buddy arrives at a target element.
 * Renders at a fixed local position within the OverlayViewport,
 * to the right of the buddy triangle.
 */

import React from "react";
import { useCursorStore } from "../stores/cursor-store";
import { DS } from "../lib/design-tokens";
import { runtimeConfig } from "../lib/runtime-config";
import { useRuntimeConfig } from "../hooks/use-runtime-config";

export const NavigationBubble: React.FC = () => {
  const navigationMode = useCursorStore((s) => s.navigationMode);
  const bubbleText = useCursorStore((s) => s.navigationBubbleText);
  const bubbleOpacity = useCursorStore((s) => s.navigationBubbleOpacity);
  const bubbleScale = useCursorStore((s) => s.navigationBubbleScale);

  const isVisible =
    navigationMode === "pointing-at-target" && bubbleText.length > 0;

  useRuntimeConfig();
  const color = runtimeConfig.cursorColor;

  if (!isVisible) return null;

  // Fixed local position — to the right of the buddy triangle
  const localX = DS.viewport.localBuddyX + 14;
  const localY = DS.viewport.localBuddyY + 2;

  return (
    <div
      style={{
        position: "absolute",
        left: localX,
        top: localY,
        transform: `scale(${bubbleScale})`,
        transition:
          "transform 0.4s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.5s ease-out",
        opacity: bubbleOpacity,
        willChange: "transform, opacity",
        pointerEvents: "none",
        transformOrigin: "top left",
      }}
    >
      <div
        style={{
          background: color,
          color: "#ffffff",
          fontSize: "11px",
          fontWeight: 500,
          fontFamily:
            '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
          padding: "6px 10px",
          borderRadius: "8px",
          maxWidth: "280px",
          whiteSpace: "normal",
          lineHeight: 1.4,
          boxShadow: `0 0 ${6 + (1.0 - bubbleScale) * 16}px ${color}80`,
        }}
      >
        {bubbleText}
      </div>
    </div>
  );
};
