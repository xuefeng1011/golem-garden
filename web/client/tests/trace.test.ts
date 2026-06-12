import { describe, it, expect } from 'vitest'
import {
  buildReplayTimeline,
  pairToolCalls,
  extractReasoning,
  aggregateKnowledge,
} from '@/utils/trace'

// ── fixtures ──────────────────────────────────────────────────────────────────

const INIT_LINE = {
  type: 'system',
  subtype: 'init',
  session_id: 'abc',
  model: 'claude-test',
}

const TEXT_LINE = {
  type: 'assistant',
  message: {
    content: [{ type: 'text', text: 'Hello world' }],
  },
}

const THINKING_LINE = {
  type: 'assistant',
  message: {
    content: [{ type: 'thinking', thinking: 'I need to think about this carefully.' }],
  },
}

const TOOL_USE_LINE = {
  type: 'assistant',
  message: {
    content: [
      {
        type: 'tool_use',
        id: 'tu_001',
        name: 'Read',
        input: { file_path: '/src/utils/trace.ts' },
      },
    ],
  },
}

const TOOL_RESULT_LINE = {
  type: 'user',
  message: {
    content: [
      {
        type: 'tool_result',
        tool_use_id: 'tu_001',
        content: 'export function buildReplayTimeline...',
        is_error: false,
      },
    ],
  },
}

const MCP_TOOL_USE_LINE = {
  type: 'assistant',
  message: {
    content: [
      {
        type: 'tool_use',
        id: 'tu_mcp_001',
        name: 'mcp__github__search_code',
        input: { query: 'trace utility' },
      },
    ],
  },
}

const RESULT_LINE = {
  type: 'result',
  subtype: 'success',
  result: 'Done',
  duration_ms: 1200,
}

const FAIL_TOOL_RESULT_LINE = {
  type: 'user',
  message: {
    content: [
      {
        type: 'tool_result',
        tool_use_id: 'tu_001',
        content: 'Permission denied',
        is_error: true,
      },
    ],
  },
}

const GREP_LINE = {
  type: 'assistant',
  message: {
    content: [
      {
        type: 'tool_use',
        id: 'tu_grep',
        name: 'Grep',
        // pattern only — no path, so aggregateKnowledge picks 'pattern' key
        input: { pattern: 'buildReplayTimeline' },
      },
    ],
  },
}

const GLOB_LINE = {
  type: 'assistant',
  message: {
    content: [
      {
        type: 'tool_use',
        id: 'tu_glob',
        name: 'Glob',
        input: { pattern: '**/*.ts' },
      },
    ],
  },
}

// ── buildReplayTimeline ───────────────────────────────────────────────────────

describe('buildReplayTimeline', () => {
  it('returns empty array for empty input', () => {
    expect(buildReplayTimeline([])).toEqual([])
  })

  it('maps system init to init event', () => {
    const events = buildReplayTimeline([INIT_LINE])
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe('init')
    expect(events[0].label).toBe('Session init')
  })

  it('maps assistant text to text event', () => {
    const events = buildReplayTimeline([TEXT_LINE])
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe('text')
    expect(events[0].detail).toContain('Hello world')
  })

  it('maps thinking block to thinking event', () => {
    const events = buildReplayTimeline([THINKING_LINE])
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe('thinking')
  })

  it('maps tool_use to tool_use event with label', () => {
    const events = buildReplayTimeline([TOOL_USE_LINE])
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe('tool_use')
    expect(events[0].label).toBe('Tool: Read')
    expect(events[0].detail).toContain('/src/utils/trace.ts')
  })

  it('maps tool_result to tool_result event', () => {
    const events = buildReplayTimeline([TOOL_RESULT_LINE])
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe('tool_result')
  })

  it('maps result line to result event', () => {
    const events = buildReplayTimeline([RESULT_LINE])
    expect(events).toHaveLength(1)
    expect(events[0].kind).toBe('result')
    expect(events[0].label).toContain('success')
  })

  it('preserves event order across multiple lines', () => {
    const events = buildReplayTimeline([INIT_LINE, THINKING_LINE, TOOL_USE_LINE, TOOL_RESULT_LINE, RESULT_LINE])
    const kinds = events.map(e => e.kind)
    expect(kinds).toEqual(['init', 'thinking', 'tool_use', 'tool_result', 'result'])
  })

  it('assigns sequential idx values', () => {
    const events = buildReplayTimeline([TEXT_LINE, TOOL_USE_LINE, RESULT_LINE])
    expect(events.map(e => e.idx)).toEqual([0, 1, 2])
  })
})

// ── pairToolCalls ─────────────────────────────────────────────────────────────

describe('pairToolCalls', () => {
  it('returns empty array for empty input', () => {
    expect(pairToolCalls([])).toEqual([])
  })

  it('pairs tool_use with matching tool_result', () => {
    const pairs = pairToolCalls([TOOL_USE_LINE, TOOL_RESULT_LINE])
    expect(pairs).toHaveLength(1)
    const p = pairs[0]
    expect(p.id).toBe('tu_001')
    expect(p.name).toBe('Read')
    expect(p.isMcp).toBe(false)
    expect(p.ok).toBe(true)
    expect(p.inputSummary).toContain('/src/utils/trace.ts')
    expect(p.resultSummary).toContain('buildReplayTimeline')
  })

  it('marks failed tool_result as ok=false', () => {
    const pairs = pairToolCalls([TOOL_USE_LINE, FAIL_TOOL_RESULT_LINE])
    expect(pairs[0].ok).toBe(false)
  })

  it('tool_use with no matching result has ok=false and empty resultSummary', () => {
    const pairs = pairToolCalls([TOOL_USE_LINE])
    expect(pairs).toHaveLength(1)
    expect(pairs[0].ok).toBe(false)
    expect(pairs[0].resultSummary).toBe('')
  })

  it('detects mcp__ prefixed tools as isMcp=true', () => {
    const pairs = pairToolCalls([MCP_TOOL_USE_LINE])
    expect(pairs[0].isMcp).toBe(true)
    expect(pairs[0].name).toBe('mcp__github__search_code')
  })

  it('filters only mcp tools when requested', () => {
    const pairs = pairToolCalls([TOOL_USE_LINE, TOOL_RESULT_LINE, MCP_TOOL_USE_LINE])
    const mcpOnly = pairs.filter(p => p.isMcp)
    expect(mcpOnly).toHaveLength(1)
    expect(mcpOnly[0].name).toBe('mcp__github__search_code')
  })
})

// ── extractReasoning ──────────────────────────────────────────────────────────

describe('extractReasoning', () => {
  it('returns empty array for empty input', () => {
    expect(extractReasoning([])).toEqual([])
  })

  it('extracts thinking blocks', () => {
    const items = extractReasoning([THINKING_LINE])
    expect(items).toHaveLength(1)
    expect(items[0].kind).toBe('thinking')
    expect(items[0].text).toContain('carefully')
  })

  it('extracts tool names as tool items', () => {
    const items = extractReasoning([TOOL_USE_LINE])
    expect(items).toHaveLength(1)
    expect(items[0].kind).toBe('tool')
    expect(items[0].text).toBe('Read')
  })

  it('interleaves thinking and tool in order', () => {
    const combined = {
      type: 'assistant',
      message: {
        content: [
          { type: 'thinking', thinking: 'Let me read the file first.' },
          { type: 'tool_use', id: 'x', name: 'Read', input: {} },
          { type: 'text', text: 'Done.' },
        ],
      },
    }
    const items = extractReasoning([combined])
    expect(items.map(i => i.kind)).toEqual(['thinking', 'tool', 'text'])
  })

  it('ignores non-assistant lines', () => {
    const items = extractReasoning([RESULT_LINE, TOOL_RESULT_LINE])
    expect(items).toHaveLength(0)
  })
})

// ── aggregateKnowledge ────────────────────────────────────────────────────────

describe('aggregateKnowledge', () => {
  it('returns empty array for empty input', () => {
    expect(aggregateKnowledge([])).toEqual([])
  })

  it('counts Read tool file_path references', () => {
    const refs = aggregateKnowledge([TOOL_USE_LINE, TOOL_RESULT_LINE])
    expect(refs).toHaveLength(1)
    expect(refs[0].ref).toBe('/src/utils/trace.ts')
    expect(refs[0].count).toBe(1)
    expect(refs[0].tools).toContain('Read')
  })

  it('counts Grep pattern references', () => {
    const refs = aggregateKnowledge([GREP_LINE])
    expect(refs[0].ref).toBe('buildReplayTimeline')
    expect(refs[0].tools).toContain('Grep')
  })

  it('counts Glob pattern references', () => {
    const refs = aggregateKnowledge([GLOB_LINE])
    expect(refs[0].ref).toBe('**/*.ts')
    expect(refs[0].tools).toContain('Glob')
  })

  it('aggregates repeated references and sorts by count descending', () => {
    const repeated = {
      type: 'assistant',
      message: {
        content: [
          { type: 'tool_use', id: 'a', name: 'Read', input: { file_path: '/src/main.ts' } },
          { type: 'tool_use', id: 'b', name: 'Read', input: { file_path: '/src/main.ts' } },
          { type: 'tool_use', id: 'c', name: 'Read', input: { file_path: '/src/other.ts' } },
        ],
      },
    }
    const refs = aggregateKnowledge([repeated])
    expect(refs[0].ref).toBe('/src/main.ts')
    expect(refs[0].count).toBe(2)
    expect(refs[1].ref).toBe('/src/other.ts')
    expect(refs[1].count).toBe(1)
  })

  it('ignores non-knowledge tools like Bash', () => {
    const bashLine = {
      type: 'assistant',
      message: {
        content: [
          { type: 'tool_use', id: 'bash1', name: 'Bash', input: { command: 'ls -la' } },
        ],
      },
    }
    const refs = aggregateKnowledge([bashLine])
    expect(refs).toHaveLength(0)
  })

  it('collects tool names per ref', () => {
    const combined = {
      type: 'assistant',
      message: {
        content: [
          { type: 'tool_use', id: 'r1', name: 'Read', input: { file_path: '/shared.ts' } },
          { type: 'tool_use', id: 'g1', name: 'Grep', input: { pattern: '/shared.ts' } },
        ],
      },
    }
    const refs = aggregateKnowledge([combined])
    const shared = refs.find(r => r.ref === '/shared.ts')
    expect(shared).toBeDefined()
    expect(shared!.tools).toContain('Read')
    // Grep uses 'pattern' not 'file_path', so '/shared.ts' would be via Grep too
    const grepRef = refs.find(r => r.ref === '/shared.ts' && r.tools.includes('Grep'))
    // both may land on same ref since pattern matches the string
    expect(refs.length).toBeGreaterThanOrEqual(1)
  })
})
