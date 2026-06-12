/**
 * Message windowing helpers for MessageList.
 *
 * Renders only the last WINDOW_SIZE messages and lets the user load
 * WINDOW_SIZE more at a time by clicking a "show older" button.
 * Pure functions — no Vue reactivity — so they are trivially testable.
 */

export const WINDOW_SIZE = 80

export interface WindowState {
  /** Index in the full messages array from which we start showing. */
  startIndex: number
}

/**
 * Return the initial window state for a given total message count.
 * Always starts from the tail (last WINDOW_SIZE messages).
 */
export function initialWindowState(totalCount: number): WindowState {
  return { startIndex: Math.max(0, totalCount - WINDOW_SIZE) }
}

/**
 * How many messages are hidden before the current window.
 */
export function hiddenCount(state: WindowState): number {
  return state.startIndex
}

/**
 * Expand the window by WINDOW_SIZE more messages toward the top.
 * Returns a new state object (immutable).
 */
export function expandWindow(state: WindowState): WindowState {
  return { startIndex: Math.max(0, state.startIndex - WINDOW_SIZE) }
}

/**
 * Slice the messages array according to the current window state.
 */
export function applyWindow<T>(messages: T[], state: WindowState): T[] {
  if (state.startIndex <= 0) return messages
  return messages.slice(state.startIndex)
}
