/**
 * Buddy Navigation Hook
 *
 * Orchestrates the full flight sequence:
 *   1. Listen for "cursor:fly-to" events
 *   2. Fly the buddy along a bezier arc to the target
 *   3. Show a speech bubble with character streaming
 *   4. Hold for 3 seconds
 *   5. Fly back to the cursor
 *   6. Resume cursor following
 *
 * Ported from OverlayWindow.swift's startNavigatingToElement,
 * animateBezierFlightArc, startPointingAtElement, startFlyingBackToCursor.
 */

import { useEffect, useRef, useCallback } from "react";
import { useCursorStore, type FlyToTarget } from "../stores/cursor-store";
import { eventBus } from "../events/event-bus";
import { startBezierFlight } from "../lib/bezier-flight";
import { moveOverlayWindow, setFollowingCursor } from "../lib/move-overlay-window";
import { DS } from "../lib/design-tokens";

export function useBuddyNavigation() {
  const cancelFlightRef = useRef<(() => void) | null>(null);
  const holdTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const streamTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const startReturnFlightRef = useRef<() => void>(() => {});

  // Use stable action references from the store — no reactive subscriptions needed.
  // Position reads are done imperatively via getState() inside callbacks.
  const setBuddyPosition = useCursorStore((s) => s.setBuddyPosition);
  const setNavigationMode = useCursorStore((s) => s.setNavigationMode);
  const setTriangleRotationDegrees = useCursorStore((s) => s.setTriangleRotationDegrees);
  const setBuddyFlightScale = useCursorStore((s) => s.setBuddyFlightScale);
  const setNavigationBubbleText = useCursorStore((s) => s.setNavigationBubbleText);
  const setNavigationBubbleOpacity = useCursorStore((s) => s.setNavigationBubbleOpacity);
  const setNavigationBubbleScale = useCursorStore((s) => s.setNavigationBubbleScale);
  const setIsReturningToCursor = useCursorStore((s) => s.setIsReturningToCursor);
  const setCursorPositionAtNavigationStart = useCursorStore((s) => s.setCursorPositionAtNavigationStart);
  const resetToFollowingCursor = useCursorStore((s) => s.resetToFollowingCursor);

  /** Cancel any in-progress animation and clean up timers */
  const cancelEverything = useCallback(() => {
    cancelFlightRef.current?.();
    cancelFlightRef.current = null;
    if (holdTimeoutRef.current) clearTimeout(holdTimeoutRef.current);
    if (streamTimeoutRef.current) clearTimeout(streamTimeoutRef.current);
    holdTimeoutRef.current = null;
    streamTimeoutRef.current = null;
  }, []);

  /** Stream text into the speech bubble character by character */
  const streamBubbleText = useCallback(
    (phrase: string, charIndex: number, onComplete: () => void) => {
      if (charIndex >= phrase.length) {
        onComplete();
        return;
      }

      setNavigationBubbleText(phrase.slice(0, charIndex + 1));

      // Trigger scale-bounce on first character
      if (charIndex === 0) {
        setNavigationBubbleScale(1.0);
      }

      const delay =
        DS.bubbleStreamDelayRange.min +
        Math.random() *
          (DS.bubbleStreamDelayRange.max - DS.bubbleStreamDelayRange.min);

      streamTimeoutRef.current = setTimeout(() => {
        streamBubbleText(phrase, charIndex + 1, onComplete);
      }, delay);
    },
    [setNavigationBubbleText, setNavigationBubbleScale]
  );

  /** Phase 3: Start pointing — show bubble, then schedule return flight */
  const startPointing = useCallback(
    (bubbleText?: string) => {
      setNavigationMode("pointing-at-target");
      setTriangleRotationDegrees(DS.defaultTriangleRotation);

      // Reset bubble for scale-bounce entrance
      setNavigationBubbleText("");
      setNavigationBubbleOpacity(1.0);
      setNavigationBubbleScale(0.5);

      const phrase =
        bubbleText ??
        DS.pointerPhrases[Math.floor(Math.random() * DS.pointerPhrases.length)];

      streamBubbleText(phrase, 0, () => {
        // Hold for 3 seconds, then fly back
        holdTimeoutRef.current = setTimeout(() => {
          const currentMode = useCursorStore.getState().navigationMode;
          if (currentMode !== "pointing-at-target") return;

          setNavigationBubbleOpacity(0);

          // Wait for fade out, then start return flight
          holdTimeoutRef.current = setTimeout(() => {
            const stillPointing =
              useCursorStore.getState().navigationMode === "pointing-at-target";
            if (!stillPointing) return;
            startReturnFlightRef.current();
          }, 500);
        }, DS.pointingHoldDurationMs);
      });

      eventBus.emit("cursor:arrived");
    },
    [
      setNavigationMode,
      setTriangleRotationDegrees,
      setNavigationBubbleText,
      setNavigationBubbleOpacity,
      setNavigationBubbleScale,
      streamBubbleText,
    ]
  );

  /** Phase 4: Fly back to cursor position */
  const startReturnFlight = useCallback(() => {
    const currentCursorPos = useCursorStore.getState().systemCursorPosition;
    const currentBuddyPos = useCursorStore.getState().buddyPosition;

    const destination = {
      x: currentCursorPos.x + DS.cursorOffset.x,
      y: currentCursorPos.y + DS.cursorOffset.y,
    };

    setNavigationMode("navigating-to-target");
    setIsReturningToCursor(true);
    setCursorPositionAtNavigationStart({ ...currentCursorPos });

    // Renderer keeps control of window position for return flight
    setFollowingCursor(false);

    cancelFlightRef.current = startBezierFlight({
      from: currentBuddyPos,
      to: destination,
      onFrame: (frame) => {
        setBuddyPosition(frame.position);
        setTriangleRotationDegrees(frame.rotationDegrees);
        setBuddyFlightScale(frame.scale);
        // Move the overlay window along the return flight arc
        moveOverlayWindow(frame.position.x, frame.position.y);
      },
      onComplete: () => {
        // Main process resumes cursor-following
        setFollowingCursor(true);
        resetToFollowingCursor();
        eventBus.emit("cursor:returned");
      },
    });
  }, [
    setBuddyPosition,
    setNavigationMode,
    setTriangleRotationDegrees,
    setBuddyFlightScale,
    setIsReturningToCursor,
    setCursorPositionAtNavigationStart,
    resetToFollowingCursor,
  ]);

  // Keep the ref in sync so startPointing always calls the latest version
  startReturnFlightRef.current = startReturnFlight;

  /** Phase 1: Fly to target element */
  const flyToElement = useCallback(
    (target: FlyToTarget) => {
      cancelEverything();

      const currentBuddyPos = useCursorStore.getState().buddyPosition;
      const currentCursorPos = useCursorStore.getState().systemCursorPosition;

      // Offset target so buddy sits beside the element, not on top
      const destination = {
        x: target.x + 8,
        y: target.y + 12,
      };

      setCursorPositionAtNavigationStart({ ...currentCursorPos });
      setNavigationMode("navigating-to-target");
      setIsReturningToCursor(false);

      // Renderer takes control of window position during flight
      setFollowingCursor(false);

      cancelFlightRef.current = startBezierFlight({
        from: currentBuddyPos,
        to: destination,
        onFrame: (frame) => {
          setBuddyPosition(frame.position);
          setTriangleRotationDegrees(frame.rotationDegrees);
          setBuddyFlightScale(frame.scale);
          // Move the overlay window along the flight arc (no-op in browser)
          moveOverlayWindow(frame.position.x, frame.position.y);
        },
        onComplete: () => {
          const currentMode = useCursorStore.getState().navigationMode;
          if (currentMode !== "navigating-to-target") return;
          startPointing(target.bubbleText);
        },
      });
    },
    [
      cancelEverything,
      setBuddyPosition,
      setNavigationMode,
      setTriangleRotationDegrees,
      setBuddyFlightScale,
      setIsReturningToCursor,
      setCursorPositionAtNavigationStart,
      startPointing,
    ]
  );

  // ── Wire up event bus ───────────────────────────────────────
  useEffect(() => {
    const handleFlyTo = (payload: {
      x: number;
      y: number;
      label: string;
      bubbleText?: string;
    }) => {
      flyToElement({
        x: payload.x,
        y: payload.y,
        label: payload.label,
        bubbleText: payload.bubbleText,
      });
    };

    eventBus.on("cursor:fly-to", handleFlyTo);

    return () => {
      eventBus.off("cursor:fly-to", handleFlyTo);
      cancelEverything();
      setFollowingCursor(true);
    };
  }, [flyToElement, cancelEverything]);
}
