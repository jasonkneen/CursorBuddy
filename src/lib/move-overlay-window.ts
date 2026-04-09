/**
 * Overlay Window Positioning
 *
 * Moves the Electron overlay window so the buddy triangle appears
 * at the correct screen position. Sends position to the main process
 * via IPC (fire-and-forget, no await).
 *
 * During cursor-following, the main process handles positioning
 * directly (no IPC needed). This function is only called during
 * bezier flight when the renderer controls position.
 */

import { DS } from "./design-tokens";
import { isElectronEnvironment } from "./is-electron";

/**
 * Move the overlay window so the buddy appears at (buddyScreenX, buddyScreenY).
 * No-op in browser dev mode.
 */
export function moveOverlayWindow(
  buddyScreenX: number,
  buddyScreenY: number
): void {
  if (!isElectronEnvironment()) return;

  const windowX = Math.round(buddyScreenX - DS.viewport.localBuddyX);
  const windowY = Math.round(buddyScreenY - DS.viewport.localBuddyY);

  if (!Number.isFinite(windowX) || !Number.isFinite(windowY)) return;

  window.electronAPI!.setWindowPosition(windowX, windowY);
}

/**
 * Tell the main process whether to auto-follow the cursor.
 * Call with false when starting a bezier flight (renderer takes control),
 * and true when flight ends (main process resumes cursor following).
 */
export function setFollowingCursor(following: boolean): void {
  if (!isElectronEnvironment()) return;
  window.electronAPI!.setFollowingCursor(following);
}

