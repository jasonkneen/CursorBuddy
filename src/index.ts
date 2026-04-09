/**
 * CursorBuddy — Library Entry Point
 *
 * Drop-in cursor companion for any web page.
 *
 * CDN / script tag:
 *   <script src="cursor-buddy.iife.js"></script>
 *   <script>
 *     const buddy = CursorBuddy.init();
 *     buddy.flyTo(500, 300, 'save button');
 *     buddy.flyToAnchor('top-right', 'settings');
 *   </script>
 *
 * ESM / npm:
 *   import { init } from 'cursor-buddy';
 *   const buddy = init();
 *   buddy.flyToElement(document.querySelector('.save-btn'), 'save');
 */

import React from "react";
import ReactDOM from "react-dom/client";
import { CursorOverlay } from "./components/CursorOverlay";
import { eventBus } from "./events/event-bus";
import {
  getViewportBounds,
  randomPointInViewport,
  viewportAnchor,
  type ViewportBounds,
} from "./lib/viewport-bounds";
import type { VoiceState } from "./stores/cursor-store";

// ── Public Types ──────────────────────────────────────────────

export type AnchorPosition =
  | "center"
  | "top-left"
  | "top-right"
  | "bottom-left"
  | "bottom-right"
  | "top-center"
  | "bottom-center"
  | "center-left"
  | "center-right";

export interface CursorBuddyInstance {
  /** Fly the buddy to absolute coordinates */
  flyTo(x: number, y: number, label: string, bubbleText?: string): void;
  /** Fly the buddy to a named viewport position (e.g. "top-right", "center") */
  flyToAnchor(position: AnchorPosition, label: string, bubbleText?: string): void;
  /** Fly the buddy to a DOM element's position */
  flyToElement(element: Element, label: string, bubbleText?: string): void;
  /** Fly to a random spot within the viewport */
  flyToRandom(label?: string, bubbleText?: string): void;
  /** Switch visual: idle (triangle), listening (waveform), processing (spinner), responding (triangle) */
  setVoiceState(state: VoiceState): void;
  /** Drive waveform bars (0–1). Only visible when voice state is "listening". */
  setAudioLevel(level: number): void;
  /** Start element selection mode (click-drag to select page elements) */
  startSelection(): void;
  /** Show the overlay */
  show(): void;
  /** Hide the overlay */
  hide(): void;
  /** Get the current viewport bounds */
  getViewport(): ViewportBounds;
  /** Unmount the overlay and clean up */
  destroy(): void;
  /** Listen for an overlay event (cursor:arrived, cursor:returned, selection:complete, etc.) */
  on(event: string, handler: (...args: unknown[]) => void): void;
  /** Remove an event listener */
  off(event: string, handler: (...args: unknown[]) => void): void;
}

export interface CursorBuddyOptions {
  /** Element to mount the overlay into. Defaults to document.body. */
  container?: HTMLElement;
}

// ── Init ──────────────────────────────────────────────────────

export function init(options?: CursorBuddyOptions): CursorBuddyInstance {
  const container = options?.container ?? document.body;

  const hostElement = document.createElement("div");
  hostElement.id = "cursor-buddy-root";
  hostElement.style.cssText = [
    "position:fixed",
    "inset:0",
    "pointer-events:none",
    "z-index:2147483647",
    "overflow:visible",
  ].join(";");
  container.appendChild(hostElement);

  const styleElement = document.createElement("style");
  styleElement.textContent =
    "@keyframes clicky-spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}";
  hostElement.appendChild(styleElement);

  const reactRoot = ReactDOM.createRoot(hostElement);
  reactRoot.render(React.createElement(CursorOverlay));

  return {
    flyTo(x, y, label, bubbleText) {
      eventBus.emit("cursor:fly-to", { x, y, label, bubbleText });
    },

    flyToAnchor(position, label, bubbleText) {
      const point = viewportAnchor(position);
      eventBus.emit("cursor:fly-to", { ...point, label, bubbleText });
    },

    flyToElement(element, label, bubbleText) {
      const rect = element.getBoundingClientRect();
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      eventBus.emit("cursor:fly-to", { x, y, label, bubbleText });
    },

    flyToRandom(label, bubbleText) {
      const point = randomPointInViewport();
      eventBus.emit("cursor:fly-to", {
        ...point,
        label: label ?? "random",
        bubbleText,
      });
    },

    setVoiceState(state) {
      eventBus.emit("cursor:set-voice-state", { state });
    },

    setAudioLevel(level) {
      eventBus.emit("voice:audio-level", { level });
    },

    startSelection() {
      eventBus.emit("selection:start");
    },

    show() {
      eventBus.emit("cursor:show");
    },

    hide() {
      eventBus.emit("cursor:hide");
    },

    getViewport() {
      return getViewportBounds();
    },

    destroy() {
      reactRoot.unmount();
      hostElement.remove();
      eventBus.removeAllListeners();
    },

    on(event, handler) {
      eventBus.onDynamic(event, handler);
    },

    off(event, handler) {
      eventBus.offDynamic(event, handler);
    },
  };
}

// Re-export pieces consumers might want
export { eventBus } from "./events/event-bus";
export { getViewportBounds, viewportAnchor, randomPointInViewport } from "./lib/viewport-bounds";
export { ChatPanel } from "./components/ChatPanel";
export type { ViewportBounds } from "./lib/viewport-bounds";
export type { VoiceState } from "./stores/cursor-store";
export type { EventName, AllEvents } from "./events/event-bus";
