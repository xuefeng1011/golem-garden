import { describe, it, expect } from 'vitest'
import { slugifyTitle, buildExportFilename, sessionToMarkdown } from '@/utils/download'
import type { SessionDetail } from '@/api/hermes/sessions'

function makeDetail(overrides: Partial<SessionDetail> = {}): SessionDetail {
  return {
    id: 'sess-1',
    soul_id: 'ryn',
    title: 'Test Session',
    created_at: '2026-06-12T10:00:00Z',
    updated_at: '2026-06-12T10:05:00Z',
    message_count: 2,
    messages: [
      { id: 1, role: 'user', content: 'Hello there', tool_name: null },
      { id: 2, role: 'assistant', content: 'Hi! How can I help?', tool_name: null },
    ],
    ...overrides,
  }
}

describe('slugifyTitle', () => {
  it('lowercases and hyphenates special characters', () => {
    expect(slugifyTitle('Fix: API Bug #42!')).toBe('fix-api-bug-42')
  })

  it('keeps korean characters', () => {
    expect(slugifyTitle('세션 제목 테스트')).toBe('세션-제목-테스트')
  })

  it('falls back to "session" for empty or symbol-only titles', () => {
    expect(slugifyTitle('')).toBe('session')
    expect(slugifyTitle('!!! ???')).toBe('session')
  })
})

describe('buildExportFilename', () => {
  it('builds {slug}_{YYYY-MM-DD}.{ext}', () => {
    const date = new Date(2026, 5, 12) // 2026-06-12 local
    expect(buildExportFilename('My Chat', 'json', date)).toBe('my-chat_2026-06-12.json')
    expect(buildExportFilename('My Chat', 'md', date)).toBe('my-chat_2026-06-12.md')
  })
})

describe('sessionToMarkdown', () => {
  it('renders title, metadata and role headers with content', () => {
    const md = sessionToMarkdown(makeDetail())
    expect(md).toContain('# Test Session')
    expect(md).toContain('- Session: `sess-1`')
    expect(md).toContain('- SOUL: ryn')
    expect(md).toContain('## User\n\nHello there')
    expect(md).toContain('## Assistant\n\nHi! How can I help?')
    expect(md.endsWith('\n')).toBe(true)
  })

  it('labels tool messages with the tool name', () => {
    const md = sessionToMarkdown(makeDetail({
      messages: [
        { id: 1, role: 'tool', content: '{"ok":true}', tool_name: 'forge_run' },
      ],
    }))
    expect(md).toContain('## Tool (forge_run)')
    expect(md).toContain('{"ok":true}')
  })

  it('handles empty sessions without messages', () => {
    const md = sessionToMarkdown(makeDetail({ title: '', messages: [] }))
    expect(md).toContain('# Untitled session')
    expect(md).not.toContain('## ')
  })
})
