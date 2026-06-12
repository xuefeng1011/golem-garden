// Pure client-side derivation functions for run trace lines.
// No server requests — all computation is local.

export type ReplayEventKind = 'init' | 'text' | 'thinking' | 'tool_use' | 'tool_result' | 'result'

export interface ReplayEvent {
  idx: number
  kind: ReplayEventKind
  label: string
  detail?: string
}

export interface ToolCallPair {
  id: string
  name: string
  isMcp: boolean
  inputSummary: string
  resultSummary: string
  ok: boolean
}

export type ReasoningItem =
  | { kind: 'thinking'; text: string }
  | { kind: 'tool'; text: string }
  | { kind: 'text'; text: string }

export interface KnowledgeRef {
  ref: string
  count: number
  tools: string[]
}

// ─── helpers ──────────────────────────────────────────────────────────────────

function getContentArray(line: Record<string, unknown>): unknown[] {
  const msg = line['message'] as Record<string, unknown> | undefined
  if (!msg) return []
  const content = msg['content']
  if (Array.isArray(content)) return content
  return []
}

function asRecord(v: unknown): Record<string, unknown> {
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    return v as Record<string, unknown>
  }
  return {}
}

function str(v: unknown): string {
  if (typeof v === 'string') return v
  if (v == null) return ''
  return String(v)
}

/** Extract the most meaningful 1-line summary from a tool input object. */
function summarizeInput(input: Record<string, unknown>): string {
  // Prefer path-like fields
  for (const key of ['file_path', 'path', 'pattern', 'url', 'command', 'query', 'prompt']) {
    if (typeof input[key] === 'string' && input[key]) {
      return str(input[key]).split('\n')[0].slice(0, 120)
    }
  }
  // Fallback: first string value
  for (const val of Object.values(input)) {
    if (typeof val === 'string' && val.trim()) {
      return val.split('\n')[0].slice(0, 120)
    }
  }
  return JSON.stringify(input).slice(0, 120)
}

/** Extract a 1-line summary from a tool result content. */
function summarizeResult(content: unknown): string {
  if (typeof content === 'string') return content.split('\n')[0].slice(0, 120)
  if (Array.isArray(content)) {
    for (const item of content) {
      const rec = asRecord(item)
      if (rec['type'] === 'text' && typeof rec['text'] === 'string') {
        return rec['text'].split('\n')[0].slice(0, 120)
      }
    }
  }
  if (content && typeof content === 'object') {
    return JSON.stringify(content).slice(0, 120)
  }
  return ''
}

// ─── buildReplayTimeline ──────────────────────────────────────────────────────

/**
 * Converts raw stream-json lines into an ordered replay timeline.
 * Order is preserved exactly as received.
 */
export function buildReplayTimeline(lines: object[]): ReplayEvent[] {
  const events: ReplayEvent[] = []
  let idx = 0

  for (const raw of lines) {
    const line = asRecord(raw)
    const type = str(line['type'])
    const subtype = str(line['subtype'])

    if (type === 'system' && subtype === 'init') {
      events.push({ idx: idx++, kind: 'init', label: 'Session init', detail: str(line['model'] || line['session_id']) })
      continue
    }

    if (type === 'result') {
      events.push({
        idx: idx++,
        kind: 'result',
        label: `Result: ${subtype}`,
        detail: str(line['result'] || '').slice(0, 80),
      })
      continue
    }

    if (type === 'assistant') {
      const contentArr = getContentArray(line)
      for (const item of contentArr) {
        const block = asRecord(item)
        const btype = str(block['type'])
        if (btype === 'text') {
          const text = str(block['text'])
          if (text.trim()) {
            events.push({ idx: idx++, kind: 'text', label: 'Text', detail: text.slice(0, 80) })
          }
        } else if (btype === 'thinking') {
          const thinking = str(block['thinking'])
          events.push({ idx: idx++, kind: 'thinking', label: 'Thinking', detail: thinking.slice(0, 80) })
        } else if (btype === 'tool_use') {
          const name = str(block['name'])
          const input = asRecord(block['input'])
          events.push({
            idx: idx++,
            kind: 'tool_use',
            label: `Tool: ${name}`,
            detail: summarizeInput(input),
          })
        }
      }
      continue
    }

    if (type === 'user') {
      const contentArr = getContentArray(line)
      for (const item of contentArr) {
        const block = asRecord(item)
        if (str(block['type']) === 'tool_result') {
          events.push({
            idx: idx++,
            kind: 'tool_result',
            label: 'Tool result',
            detail: summarizeResult(block['content']),
          })
        }
      }
    }
  }

  return events
}

// ─── pairToolCalls ────────────────────────────────────────────────────────────

/**
 * Match tool_use blocks with their corresponding tool_result blocks
 * via tool_use_id. Unmatched tool_use entries get empty resultSummary.
 */
export function pairToolCalls(lines: object[]): ToolCallPair[] {
  // Collect tool_use blocks
  const uses = new Map<string, { name: string; input: Record<string, unknown> }>()
  const results = new Map<string, { content: unknown; isError: boolean }>()

  for (const raw of lines) {
    const line = asRecord(raw)
    const type = str(line['type'])

    if (type === 'assistant') {
      for (const item of getContentArray(line)) {
        const block = asRecord(item)
        if (str(block['type']) === 'tool_use') {
          const id = str(block['id'])
          if (id) {
            uses.set(id, {
              name: str(block['name']),
              input: asRecord(block['input']),
            })
          }
        }
      }
    }

    if (type === 'user') {
      for (const item of getContentArray(line)) {
        const block = asRecord(item)
        if (str(block['type']) === 'tool_result') {
          const id = str(block['tool_use_id'])
          if (id) {
            results.set(id, {
              content: block['content'],
              isError: block['is_error'] === true,
            })
          }
        }
      }
    }
  }

  const pairs: ToolCallPair[] = []
  for (const [id, use] of uses) {
    const result = results.get(id)
    pairs.push({
      id,
      name: use.name,
      isMcp: use.name.startsWith('mcp__'),
      inputSummary: summarizeInput(use.input),
      resultSummary: result ? summarizeResult(result.content) : '',
      ok: result ? !result.isError : false,
    })
  }

  return pairs
}

// ─── extractReasoning ─────────────────────────────────────────────────────────

/**
 * Interleaves thinking blocks, tool_use names, and text blocks
 * in the order they appear in the stream.
 */
export function extractReasoning(lines: object[]): ReasoningItem[] {
  const items: ReasoningItem[] = []

  for (const raw of lines) {
    const line = asRecord(raw)
    if (str(line['type']) !== 'assistant') continue

    for (const item of getContentArray(line)) {
      const block = asRecord(item)
      const btype = str(block['type'])
      if (btype === 'thinking') {
        const text = str(block['thinking'])
        if (text.trim()) items.push({ kind: 'thinking', text })
      } else if (btype === 'tool_use') {
        items.push({ kind: 'tool', text: str(block['name']) })
      } else if (btype === 'text') {
        const text = str(block['text'])
        if (text.trim()) items.push({ kind: 'text', text })
      }
    }
  }

  return items
}

// ─── aggregateKnowledge ───────────────────────────────────────────────────────

const KNOWLEDGE_TOOLS = new Set([
  'Read', 'Grep', 'Glob', 'WebFetch', 'WebSearch',
  'read', 'grep', 'glob', 'web_fetch', 'web_search',
])

/**
 * Aggregates file paths, patterns, and URLs referenced in Read/Grep/Glob/WebFetch
 * tool inputs. Returns entries sorted by count descending.
 */
export function aggregateKnowledge(lines: object[]): KnowledgeRef[] {
  const refMap = new Map<string, { count: number; tools: Set<string> }>()

  for (const raw of lines) {
    const line = asRecord(raw)
    if (str(line['type']) !== 'assistant') continue

    for (const item of getContentArray(line)) {
      const block = asRecord(item)
      if (str(block['type']) !== 'tool_use') continue

      const name = str(block['name'])
      const baseName = name.split('__').pop() || name // handle mcp__ prefix
      if (!KNOWLEDGE_TOOLS.has(name) && !KNOWLEDGE_TOOLS.has(baseName)) continue

      const input = asRecord(block['input'])
      let ref = ''
      for (const key of ['file_path', 'path', 'pattern', 'url', 'query']) {
        if (typeof input[key] === 'string' && input[key]) {
          ref = str(input[key])
          break
        }
      }
      if (!ref) continue

      if (!refMap.has(ref)) {
        refMap.set(ref, { count: 0, tools: new Set() })
      }
      const entry = refMap.get(ref)!
      entry.count += 1
      entry.tools.add(baseName || name)
    }
  }

  return [...refMap.entries()]
    .map(([ref, { count, tools }]) => ({ ref, count, tools: [...tools] }))
    .sort((a, b) => b.count - a.count)
}
