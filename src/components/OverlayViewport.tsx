/**
 * Overlay Viewport
 *
 * A compact container (320×80) that follows the buddy around the screen.
 * Child components render at FIXED LOCAL positions within it — the
 * viewport itself moves to place them at the correct screen location.
 *
 * - Electron mode: the viewport IS the window. moveOverlayWindow() sets
 *   the Electron window.setPosition() imperatively at ~60fps (no React in the loop).
 * - Browser mode: a CSS-transformed div mimics the moving window,
 *   with a spring transition for smooth cursor following.
 */

import React from "react";
import { useCursorStore } from "../stores/cursor-store";
import { DS } from "../lib/design-tokens";
import { isElectronEnvironment } from "../lib/is-electron";

export const OverlayViewport: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const buddyPosition = useCursorStore((s) => s.buddyPosition);
  const navigationMode = useCursorStore((s) => s.navigationMode);

  // In Electron, the window is positioned by the main process (cursor
  // following) or by moveOverlayWindow() (during flight). We just
  // render a static container at the viewport size.
  if (isElectronEnvironment()) {
    return (
      <div
        style={{
          position: "relative",
          width: DS.viewport.width,
          height: DS.viewport.height,
          overflow: "visible",
          pointerEvents: "none",
        }}
      >
        {children}
      </div>
    );
  }

  // Browser mode: position a div via CSS transform.
  // No CSS transition — the spring physics loop in use-cursor-tracking
  // updates buddyPosition at 60fps with real damped spring math.
  const viewportScreenX = buddyPosition.x - DS.viewport.localBuddyX;
  const viewportScreenY = buddyPosition.y - DS.viewport.localBuddyY;

  return (
    <div
      style={{
        position: "fixed",
        left: 0,
        top: 0,
        width: DS.viewport.width,
        height: DS.viewport.height,
        transform: `translate(${viewportScreenX}px, ${viewportScreenY}px)`,
        willChange: "transform",
        pointerEvents: "none",
        overflow: "visible",
      }}
    >
      {children}
    </div>
  );
};
