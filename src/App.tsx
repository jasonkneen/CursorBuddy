/**
 * CursorBuddy — App Root
 *
 * The app renders a single transparent overlay. All visual elements
 * (cursor triangle, waveform, spinner, speech bubble) are positioned
 * absolutely within this overlay.
 *
 * In development (browser), move your mouse and use the demo controls
 * to test animations. In Electron, the overlay is full-screen transparent
 * and click-through.
 */

import React, { useEffect, useState } from "react";
import { CursorOverlay } from "./components/CursorOverlay";
import { DemoControls } from "./components/DemoControls";
import { ElementSelector } from "./components/ElementSelector";
import { eventBus } from "./events/event-bus";
import { isElectronEnvironment } from "./lib/is-electron";

export const App: React.FC = () => {
  const [showDemoControls, setShowDemoControls] = useState(false);

  useEffect(() => {
    // Show demo controls only in browser dev mode (not Electron)
    if (!isElectronEnvironment()) {
      setShowDemoControls(true);
    }
  }, []);

  return (
    <>
      <CursorOverlay />
      <ElementSelector />
      {showDemoControls && <DemoControls />}

      {/* Global keyframe animations */}
      <style>{`
        @keyframes clicky-spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }
      `}</style>
    </>
  );
};
