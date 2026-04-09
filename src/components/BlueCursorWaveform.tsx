/**
 * Blue Cursor Waveform
 *
 * Audio-reactive waveform bars shown while listening.
 * Renders at a fixed local position within the OverlayViewport.
 */

import React, { useRef, useEffect, useCallback } from "react";
import { useCursorStore } from "../stores/cursor-store";
import { DS } from "../lib/design-tokens";
import { runtimeConfig } from "../lib/runtime-config";
import { useRuntimeConfig } from "../hooks/use-runtime-config";

const BAR_COUNT = 5;
const BAR_PROFILE = [0.4, 0.7, 1.0, 0.7, 0.4];
const BAR_WIDTH = 2;
const BAR_GAP = 2;
const BAR_RADIUS = 1.5;

export const BlueCursorWaveform: React.FC = () => {
  const voiceState = useCursorStore((s) => s.voiceState);
  const audioLevel = useCursorStore((s) => s.audioLevel);
  const cursorOpacity = useCursorStore((s) => s.cursorOpacity);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number | null>(null);
  const audioLevelRef = useRef(audioLevel);
  audioLevelRef.current = audioLevel;
  useRuntimeConfig();

  const color = runtimeConfig.cursorColor;
  const isVisible = voiceState === "listening";

  const draw = useCallback(
    (timestamp: number) => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;

      const dpr = window.devicePixelRatio || 1;
      const totalWidth = BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP;
      const logicalHeight = 30;
      canvas.width = totalWidth * dpr;
      canvas.height = logicalHeight * dpr;
      canvas.style.width = `${totalWidth}px`;
      canvas.style.height = `${logicalHeight}px`;
      ctx.scale(dpr, dpr);
      ctx.clearRect(0, 0, totalWidth, logicalHeight);

      const animationPhase = (timestamp / 1000) * 3.6;
      const currentAudioLevel = audioLevelRef.current;

      for (let barIndex = 0; barIndex < BAR_COUNT; barIndex++) {
        const phaseOffset = animationPhase + barIndex * 0.35;
        const normalizedLevel = Math.max(currentAudioLevel - 0.008, 0);
        const easedLevel = Math.pow(Math.min(normalizedLevel * 2.85, 1), 0.76);
        const reactiveHeight = easedLevel * 10 * BAR_PROFILE[barIndex];
        const idlePulse = ((Math.sin(phaseOffset) + 1) / 2) * 1.5;
        const barHeight = 3 + reactiveHeight + idlePulse;

        const barX = barIndex * (BAR_WIDTH + BAR_GAP);
        const barY = (logicalHeight - barHeight) / 2;

        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.roundRect(barX, barY, BAR_WIDTH, barHeight, BAR_RADIUS);
        ctx.fill();
      }

      animationRef.current = requestAnimationFrame(draw);
    },
    []
  );

  useEffect(() => {
    if (isVisible) {
      animationRef.current = requestAnimationFrame(draw);
    }
    return () => {
      if (animationRef.current !== null) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [isVisible, draw]);

  // Fixed local position — centered on localBuddy
  const localX = DS.viewport.localBuddyX;
  const localY = DS.viewport.localBuddyY;

  return (
    <div
      style={{
        position: "absolute",
        left: localX - 10,
        top: localY - 15,
        opacity: isVisible ? cursorOpacity : 0,
        transition: "opacity 0.15s ease",
        willChange: "opacity",
        pointerEvents: "none",
        filter: `drop-shadow(0 0 6px ${color}99)`,
      }}
    >
      <canvas ref={canvasRef} />
    </div>
  );
};
