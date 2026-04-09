/**
 * useRuntimeConfig Hook
 *
 * Forces a re-render whenever the runtime configuration changes.
 * Extracted from the repeated pattern in BlueCursorSpinner,
 * BlueCursorTriangle, BlueCursorWaveform, and NavigationBubble.
 */

import { useState, useEffect } from 'react';
import { onConfigChange } from '../lib/runtime-config';

export function useRuntimeConfig() {
  const [, forceUpdate] = useState(0);
  useEffect(() => onConfigChange(() => forceUpdate((n) => n + 1)), []);
}
