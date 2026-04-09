/**
 * Demo Controls
 *
 * In-browser development panel for testing the cursor overlay
 * without Electron. Lets you trigger voice states, fly-to animations,
 * and audio level changes via buttons.
 *
 * Only rendered when running in a browser (not inside Electron).
 */

import React, { useState, useCallback, useRef, useEffect } from "react";
import { eventBus } from "../events/event-bus";
import { useCursorStore } from "../stores/cursor-store";
import { randomPointInViewport } from "../lib/viewport-bounds";

export const DemoControls: React.FC = () => {
  const [isSimulatingAudio, setIsSimulatingAudio] = useState(false);
  const audioIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const voiceState = useCursorStore((s) => s.voiceState);
  const navigationMode = useCursorStore((s) => s.navigationMode);

  const setVoiceState = useCallback(
    (state: "idle" | "listening" | "processing" | "responding") => {
      eventBus.emit("cursor:set-voice-state", { state });
    },
    []
  );

  const flyToRandomSpot = useCallback(() => {
    const point = randomPointInViewport();
    const labels = [
      "search bar",
      "save button",
      "settings icon",
      "file menu",
      "close tab",
    ];
    const label = labels[Math.floor(Math.random() * labels.length)];
    eventBus.emit("cursor:fly-to", { ...point, label });
  }, []);

  const flyToWithCustomText = useCallback(() => {
    const point = randomPointInViewport();
    eventBus.emit("cursor:fly-to", {
      ...point,
      label: "demo element",
      bubbleText: "nice wallpaper choices",
    });
  }, []);

  const toggleAudioSimulation = useCallback(() => {
    if (isSimulatingAudio) {
      if (audioIntervalRef.current) {
        clearInterval(audioIntervalRef.current);
        audioIntervalRef.current = null;
      }
      eventBus.emit("voice:audio-level", { level: 0 });
      setIsSimulatingAudio(false);
    } else {
      setVoiceState("listening");
      setIsSimulatingAudio(true);
      audioIntervalRef.current = setInterval(() => {
        // Simulate natural speech-like audio levels
        const level = Math.random() * 0.7 + Math.sin(Date.now() / 200) * 0.15;
        eventBus.emit("voice:audio-level", { level: Math.max(0, Math.min(1, level)) });
      }, 50);
    }
  }, [isSimulatingAudio, setVoiceState]);

  // Clean up audio simulation on unmount
  useEffect(() => {
    return () => {
      if (audioIntervalRef.current) {
        clearInterval(audioIntervalRef.current);
      }
    };
  }, []);

  return (
    <div
      style={{
        position: "fixed",
        bottom: 20,
        left: 20,
        background: "rgba(16, 18, 17, 0.95)",
        border: "1px solid rgba(55, 59, 57, 0.8)",
        borderRadius: 12,
        padding: 16,
        color: "#ECEEED",
        fontFamily:
          '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace',
        fontSize: 12,
        pointerEvents: "auto",
        zIndex: 9999,
        minWidth: 260,
        backdropFilter: "blur(20px)",
        boxShadow: "0 8px 32px rgba(0,0,0,0.4)",
      }}
    >
      <div
        style={{
          marginBottom: 12,
          fontWeight: 600,
          fontSize: 13,
          color: "#3b82f6",
        }}
      >
        🔵 CursorBuddy — Dev Controls
      </div>

      <div style={{ marginBottom: 8, color: "#6B736F" }}>
        Voice: <span style={{ color: "#ADB5B2" }}>{voiceState}</span>
        {" · "}
        Nav: <span style={{ color: "#ADB5B2" }}>{navigationMode}</span>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
        <div style={{ display: "flex", gap: 6 }}>
          <DemoButton onClick={() => setVoiceState("idle")} label="Idle" active={voiceState === "idle"} />
          <DemoButton onClick={() => setVoiceState("listening")} label="Listen" active={voiceState === "listening"} />
          <DemoButton onClick={() => setVoiceState("processing")} label="Process" active={voiceState === "processing"} />
          <DemoButton onClick={() => setVoiceState("responding")} label="Respond" active={voiceState === "responding"} />
        </div>

        <div style={{ display: "flex", gap: 6 }}>
          <DemoButton onClick={flyToRandomSpot} label="Fly to random" />
          <DemoButton onClick={flyToWithCustomText} label="Fly + bubble" />
        </div>

        <DemoButton
          onClick={toggleAudioSimulation}
          label={isSimulatingAudio ? "Stop audio sim" : "Simulate audio"}
          active={isSimulatingAudio}
        />
      </div>

      <div
        style={{
          marginTop: 10,
          paddingTop: 8,
          borderTop: "1px solid rgba(55, 59, 57, 0.5)",
          color: "#6B736F",
          fontSize: 10,
          lineHeight: 1.4,
        }}
      >
        Move your mouse to see the cursor follow.
        <br />
        In Electron, this panel is hidden.
      </div>
    </div>
  );
};

const DemoButton: React.FC<{
  onClick: () => void;
  label: string;
  active?: boolean;
}> = ({ onClick, label, active }) => (
  <button
    onClick={onClick}
    style={{
      background: active ? "rgba(59, 130, 246, 0.2)" : "rgba(32, 34, 33, 0.8)",
      border: `1px solid ${active ? "rgba(59, 130, 246, 0.4)" : "rgba(55, 59, 57, 0.6)"}`,
      color: active ? "#60a5fa" : "#ADB5B2",
      borderRadius: 6,
      padding: "4px 10px",
      fontSize: 11,
      fontFamily: "inherit",
      cursor: "pointer",
      pointerEvents: "auto",
      transition: "all 0.15s ease",
      flex: 1,
    }}
    onMouseEnter={(e) => {
      (e.target as HTMLButtonElement).style.background = "rgba(59, 130, 246, 0.15)";
      (e.target as HTMLButtonElement).style.borderColor = "rgba(59, 130, 246, 0.3)";
    }}
    onMouseLeave={(e) => {
      (e.target as HTMLButtonElement).style.background = active
        ? "rgba(59, 130, 246, 0.2)"
        : "rgba(32, 34, 33, 0.8)";
      (e.target as HTMLButtonElement).style.borderColor = active
        ? "rgba(59, 130, 246, 0.4)"
        : "rgba(55, 59, 57, 0.6)";
    }}
  >
    {label}
  </button>
);
