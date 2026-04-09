/**
 * Element Selector
 *
 * Click-and-drag to select a region on the page.
 * Captures the selected area's bounding rect and the HTML elements
 * within it, then emits via the event bus.
 *
 * Activated via event bus: "selection:start"
 * Deactivated on mouse-up or Escape.
 * Result emitted as: "selection:complete" with { bounds, html, elementCount }
 *
 * Works in both web embed and Electron.
 */

import React, { useState, useRef, useEffect, useCallback } from "react";
import { eventBus } from "../events/event-bus";

interface SelectionBounds {
  x: number;
  y: number;
  width: number;
  height: number;
}

export const ElementSelector: React.FC = () => {
  const [isActive, setIsActive] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [selectionBounds, setSelectionBounds] = useState<SelectionBounds | null>(null);
  const startPointRef = useRef<{ x: number; y: number } | null>(null);

  // ── Activate/deactivate via event bus ──────────────────────
  useEffect(() => {
    const handleStart = () => setIsActive(true);
    const handleStop = () => {
      setIsActive(false);
      setIsDragging(false);
      setSelectionBounds(null);
    };

    eventBus.on("selection:start", handleStart);
    eventBus.on("selection:cancel", handleStop);

    return () => {
      eventBus.off("selection:start", handleStart);
      eventBus.off("selection:cancel", handleStop);
    };
  }, []);

  // ── Escape key to cancel ──────────────────────────────────
  useEffect(() => {
    if (!isActive) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setIsActive(false);
        setIsDragging(false);
        setSelectionBounds(null);
      }
    };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [isActive]);

  // ── Mouse handlers ────────────────────────────────────────
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    startPointRef.current = { x: e.clientX, y: e.clientY };
    setIsDragging(true);
    setSelectionBounds({ x: e.clientX, y: e.clientY, width: 0, height: 0 });
  }, []);

  const handleMouseMove = useCallback(
    (e: React.MouseEvent) => {
      if (!isDragging || !startPointRef.current) return;
      const startX = startPointRef.current.x;
      const startY = startPointRef.current.y;
      setSelectionBounds({
        x: Math.min(startX, e.clientX),
        y: Math.min(startY, e.clientY),
        width: Math.abs(e.clientX - startX),
        height: Math.abs(e.clientY - startY),
      });
    },
    [isDragging]
  );

  const handleMouseUp = useCallback(() => {
    if (!isDragging || !selectionBounds) return;
    setIsDragging(false);

    // Only process if selection is meaningful (> 10px)
    if (selectionBounds.width > 10 && selectionBounds.height > 10) {
      // Collect elements that overlap the selection
      const selectedElements: string[] = [];
      const allElements = document.querySelectorAll("*");
      allElements.forEach((el) => {
        if (el.closest("#cursor-buddy-root")) return; // Skip our own elements
        const rect = el.getBoundingClientRect();
        const overlaps =
          rect.left < selectionBounds.x + selectionBounds.width &&
          rect.right > selectionBounds.x &&
          rect.top < selectionBounds.y + selectionBounds.height &&
          rect.bottom > selectionBounds.y;
        if (overlaps && el.innerHTML.trim()) {
          selectedElements.push(el.outerHTML.slice(0, 500)); // Truncate long elements
        }
      });

      eventBus.emit("selection:complete", {
        bounds: selectionBounds,
        html: selectedElements.slice(0, 20).join("\n"), // Cap at 20 elements
        elementCount: selectedElements.length,
      });
    }

    setIsActive(false);
    setSelectionBounds(null);
  }, [isDragging, selectionBounds]);

  if (!isActive) return null;

  return (
    <div
      onMouseDown={handleMouseDown}
      onMouseMove={handleMouseMove}
      onMouseUp={handleMouseUp}
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 2147483646, // Just below cursor-buddy-root
        cursor: "crosshair",
        pointerEvents: "auto",
        background: isDragging ? "rgba(59, 130, 246, 0.05)" : "transparent",
      }}
    >
      {selectionBounds && selectionBounds.width > 0 && (
        <div
          style={{
            position: "absolute",
            left: selectionBounds.x,
            top: selectionBounds.y,
            width: selectionBounds.width,
            height: selectionBounds.height,
            border: "2px solid #3b82f6",
            borderRadius: 4,
            background: "rgba(59, 130, 246, 0.08)",
            pointerEvents: "none",
            boxShadow: "0 0 0 9999px rgba(0, 0, 0, 0.15)",
          }}
        />
      )}

      {/* Instruction overlay */}
      {!isDragging && (
        <div
          style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -50%)",
            background: "rgba(16, 18, 17, 0.9)",
            color: "#e2e8f0",
            padding: "12px 20px",
            borderRadius: 12,
            fontSize: 13,
            fontFamily: "-apple-system, sans-serif",
            textAlign: "center",
            pointerEvents: "none",
            border: "1px solid rgba(59, 130, 246, 0.2)",
            backdropFilter: "blur(20px)",
          }}
        >
          Click and drag to select elements
          <br />
          <span style={{ fontSize: 11, color: "#64748b" }}>
            Press Escape to cancel
          </span>
        </div>
      )}
    </div>
  );
};
