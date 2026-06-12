import { describe, it, expect } from 'vitest'
import { repairUnclosedFences } from '@/utils/fence-repair'

describe('repairUnclosedFences', () => {
  // Case 1: odd fence count (streaming mid-code-block) → temporary close added
  it('closes an unclosed fence', () => {
    const input = 'Here is code:\n```\nconst a = 1'
    expect(repairUnclosedFences(input)).toBe('Here is code:\n```\nconst a = 1\n```')
  })

  // Case 2: even fence count (complete block) → untouched
  it('leaves a balanced fence pair untouched', () => {
    const input = '```\nconst a = 1\n```\ndone'
    expect(repairUnclosedFences(input)).toBe(input)
  })

  // Case 3: language tag on the opening fence still counts as a fence
  it('counts fences with a language tag', () => {
    const input = '```typescript\nconst a: number = 1'
    expect(repairUnclosedFences(input)).toBe('```typescript\nconst a: number = 1\n```')
  })

  // Case 4: inline code (single backticks) is never touched
  it('ignores inline code backticks', () => {
    const input = 'Use `foo()` and `bar()` here'
    expect(repairUnclosedFences(input)).toBe(input)
  })

  // Case 5: no fences at all → untouched (fast path)
  it('returns plain text unchanged', () => {
    const input = 'Just a plain sentence.'
    expect(repairUnclosedFences(input)).toBe(input)
  })

  // Case 6: trailing newline → closing fence appended without a blank line
  it('does not add an extra blank line when input ends with newline', () => {
    const input = '```python\nprint(1)\n'
    expect(repairUnclosedFences(input)).toBe('```python\nprint(1)\n```')
  })

  // Case 7: multiple complete blocks plus one unclosed → only one close added
  it('closes only the last unclosed fence among multiple blocks', () => {
    const input = '```js\na\n```\ntext\n```js\nb'
    expect(repairUnclosedFences(input)).toBe('```js\na\n```\ntext\n```js\nb\n```')
  })

  // Case 8: indented fence (up to 3 spaces) is still a fence per CommonMark
  it('counts fences indented up to three spaces', () => {
    const input = '   ```\ncode'
    expect(repairUnclosedFences(input)).toBe('   ```\ncode\n```')
  })

  // Case 9: ``` appearing mid-line (not at line start) is not a fence delimiter
  it('ignores triple backticks that are not at line start', () => {
    const input = 'wrap with ``` to fence code'
    expect(repairUnclosedFences(input)).toBe(input)
  })

  // Case 10: empty string → untouched
  it('returns an empty string unchanged', () => {
    expect(repairUnclosedFences('')).toBe('')
  })
})
