import { describe, it, expect } from 'vitest'
import { validateForgeArg } from '@/utils/forge-args'

describe('validateForgeArg', () => {
  it('accepts a plain value', () => {
    expect(validateForgeArg('Grow the garden')).toBeNull()
  })

  it('rejects newlines', () => {
    expect(validateForgeArg('line1\nline2')).toBe('newline')
    expect(validateForgeArg('line1\rline2')).toBe('newline')
  })

  it('rejects values over 512 characters', () => {
    expect(validateForgeArg('a'.repeat(513))).toBe('tooLong')
    expect(validateForgeArg('a'.repeat(512))).toBeNull()
  })

  it.each([';', '|', '&', '<', '>', '`', '$'])(
    'rejects the forbidden character %s (gateway _FORBIDDEN_ARG_CHARS parity)',
    (char) => {
      expect(validateForgeArg(`before${char}after`)).toBe('forbiddenChars')
    },
  )
})
