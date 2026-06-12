import { describe, it, expect } from 'vitest'
import {
  WINDOW_SIZE,
  initialWindowState,
  hiddenCount,
  expandWindow,
  applyWindow,
} from '@/utils/message-window'

describe('message-window', () => {
  it('shows all messages when total is below WINDOW_SIZE', () => {
    const state = initialWindowState(50)
    expect(state.startIndex).toBe(0)
    expect(hiddenCount(state)).toBe(0)

    const msgs = Array.from({ length: 50 }, (_, i) => i)
    expect(applyWindow(msgs, state)).toEqual(msgs)
  })

  it('truncates to last WINDOW_SIZE when total exceeds limit', () => {
    const total = WINDOW_SIZE + 30
    const state = initialWindowState(total)
    expect(state.startIndex).toBe(30)
    expect(hiddenCount(state)).toBe(30)

    const msgs = Array.from({ length: total }, (_, i) => i)
    const windowed = applyWindow(msgs, state)
    expect(windowed).toHaveLength(WINDOW_SIZE)
    expect(windowed[0]).toBe(30)
    expect(windowed[windowed.length - 1]).toBe(total - 1)
  })

  it('expanding window moves startIndex back by WINDOW_SIZE', () => {
    const state = initialWindowState(WINDOW_SIZE * 3)
    // startIndex = WINDOW_SIZE * 2
    expect(state.startIndex).toBe(WINDOW_SIZE * 2)

    const expanded = expandWindow(state)
    expect(expanded.startIndex).toBe(WINDOW_SIZE)
    expect(hiddenCount(expanded)).toBe(WINDOW_SIZE)

    const fullyExpanded = expandWindow(expanded)
    expect(fullyExpanded.startIndex).toBe(0)
    expect(hiddenCount(fullyExpanded)).toBe(0)
  })
})
