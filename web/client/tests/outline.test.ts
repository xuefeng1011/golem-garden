import { describe, it, expect } from 'vitest'
import { extractOutline } from '@/utils/outline'

describe('extractOutline', () => {
  // Case 1: basic extraction with collision-free anchor ids
  it('extracts headings with level, text and anchorId', () => {
    const md = '# Title\n\nbody text\n\n## Section\n\nmore text'
    const items = extractOutline(md, 'msg-1')
    expect(items).toEqual([
      { level: 1, text: 'Title', anchorId: 'outline-msg-1-0', messageId: 'msg-1', headingIndex: 0 },
      { level: 2, text: 'Section', anchorId: 'outline-msg-1-1', messageId: 'msg-1', headingIndex: 1 },
    ])
  })

  // Case 2: levels 1-3 captured, level 4+ ignored
  it('captures # through ### and ignores #### and deeper', () => {
    const md = '# H1\n## H2\n### H3\n#### H4\n##### H5'
    const items = extractOutline(md, 'm')
    expect(items.map(i => i.level)).toEqual([1, 2, 3])
    expect(items.map(i => i.text)).toEqual(['H1', 'H2', 'H3'])
  })

  // Case 3: # inside a fenced code block is not a heading
  it('excludes # lines inside code fences', () => {
    const md = '# Real\n```bash\n# comment in code\n## also code\n```\n## After'
    const items = extractOutline(md, 'm')
    expect(items.map(i => i.text)).toEqual(['Real', 'After'])
  })

  // Case 4: empty / falsy input
  it('returns an empty array for empty input', () => {
    expect(extractOutline('', 'm')).toEqual([])
  })

  // Case 5: hash without a following space is not a heading
  it('ignores hashes without a trailing space', () => {
    expect(extractOutline('#nospace\n#!/bin/bash', 'm')).toEqual([])
  })

  // Case 6: unclosed fence (streaming) suppresses everything after it
  it('treats an unclosed fence as still open', () => {
    const md = '# Before\n```\n# inside unclosed fence'
    const items = extractOutline(md, 'm')
    expect(items.map(i => i.text)).toEqual(['Before'])
  })

  // Case 7: closing hash sequence is stripped (ATX closed style)
  it('strips trailing closing hashes', () => {
    const items = extractOutline('## Title ##', 'm')
    expect(items[0].text).toBe('Title')
  })

  // Case 8: anchor ids are unique across messages
  it('namespaces anchor ids by message id', () => {
    const a = extractOutline('# Same', 'msg-a')
    const b = extractOutline('# Same', 'msg-b')
    expect(a[0].anchorId).not.toBe(b[0].anchorId)
  })

  // Case 9: tilde fences also toggle code state
  it('excludes headings inside tilde fences', () => {
    const md = '~~~\n# in tilde fence\n~~~\n# Out'
    const items = extractOutline(md, 'm')
    expect(items.map(i => i.text)).toEqual(['Out'])
  })
})
