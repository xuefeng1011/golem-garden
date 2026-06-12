import { describe, it, expect } from 'vitest'
import { fmtUsd } from '@/utils/format'

describe('fmtUsd', () => {
  it('returns em dash for null', () => {
    expect(fmtUsd(null)).toBe('—')
  })

  it('returns em dash for undefined', () => {
    expect(fmtUsd(undefined)).toBe('—')
  })

  it('returns em dash for NaN', () => {
    expect(fmtUsd(NaN)).toBe('—')
  })

  it('formats zero with 3 decimals', () => {
    expect(fmtUsd(0)).toBe('$0.000')
  })

  it('formats sub-dollar amounts with 3 decimals', () => {
    expect(fmtUsd(0.0156)).toBe('$0.016')
    expect(fmtUsd(0.5)).toBe('$0.500')
    expect(fmtUsd(0.999)).toBe('$0.999')
  })

  it('formats amounts >= 1 with 2 decimals', () => {
    expect(fmtUsd(1)).toBe('$1.00')
    expect(fmtUsd(1.234)).toBe('$1.23')
    expect(fmtUsd(12.5)).toBe('$12.50')
  })
})
