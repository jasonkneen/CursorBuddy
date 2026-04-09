/**
 * Blue Cursor Triangle
 *
 * The buddy's signature blue triangle. Shape matches the Swift
 * Triangle exactly — equilateral using sqrt(3)/2 height:
 *
 *   height = size × √3 / 2
 *   top vertex:    (midX, midY - height/1.5)
 *   bottom-left:   (midX - size/2, midY + height/3)
 *   bottom-right:  (midX + size/2, midY + height/3)
 *
 * For a 16×16 viewBox (size=16):
 *   height = 16 × 0.866 = 13.86
 *   top:    (8, 8 - 9.24)  = (8, -1.24)  → clamped visually
 *   left:   (0, 8 + 4.62)  = (0, 12.62)
 *   right:  (16, 12.62)
 *
 * Rotation, scale, and glow all animate. Fixed local position.
 */

import React from "react";
import { useCursorStore } from "../stores/cursor-store";
import { DS } from "../lib/design-tokens";
import { runtimeConfig } from "../lib/runtime-config";
import { useRuntimeConfig } from "../hooks/use-runtime-config";

export const BlueCursorTriangle: React.FC = () => {
  const voiceState = useCursorStore((s) => s.voiceState);
  const rotationDegrees = useCursorStore((s) => s.triangleRotationDegrees);
  const flightScale = useCursorStore((s) => s.buddyFlightScale);
  const cursorOpacity = useCursorStore((s) => s.cursorOpacity);

  // Re-render when runtime config changes (color, size, glow)
  useRuntimeConfig();

  const color = runtimeConfig.cursorColor;
  const size = runtimeConfig.cursorSize;
  const isVisible = voiceState === "idle" || voiceState === "responding";

  // Glow intensifies during flight
  const glowRadius = runtimeConfig.glowIntensity + (flightScale - 1.0) * 20;

  const localX = DS.viewport.localBuddyX;
  const localY = DS.viewport.localBuddyY;
  const half = size / 2;

  // Recompute triangle points for current size
  const triH = size * Math.sqrt(3) / 2;
  const topY = half - triH / 1.5;
  const botY = half + triH / 3;
  const pts = `${half},${topY.toFixed(1)} 0,${botY.toFixed(1)} ${size},${botY.toFixed(1)}`;

  return (
    <div
      style={{
        position: "absolute",
        left: localX - half,
        top: localY - half,
        transform: `rotate(${rotationDegrees}deg) scale(${flightScale})`,
        opacity: isVisible ? cursorOpacity : 0,
        transition: "opacity 0.25s ease-in",
        willChange: "transform, opacity",
        pointerEvents: "none",
        filter: `drop-shadow(0 0 ${glowRadius}px ${color})`,
      }}
    >
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <polygon points={pts} fill={color} />
      </svg>
    </div>
  );
};
