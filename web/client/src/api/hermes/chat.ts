import { request, getBaseUrlValue } from '../client'

export interface ChatMessage {
  role: 'user' | 'assistant' | 'system'
  content: string
}

export interface StartRunRequest {
  input: string | ChatMessage[]
  instructions?: string
  conversation_history?: ChatMessage[]
  session_id?: string
  model?: string
  soul_id?: string
  project_id?: string
}

export interface StartRunResponse {
  run_id: string
  status: string
}

// SSE event types from /v1/runs/{id}/events
export interface RunEvent {
  event: string
  run_id?: string
  delta?: string
  // message.thinking — extended-thinking 델타 텍스트
  text?: string
  tool?: string
  name?: string
  preview?: string
  timestamp?: number
  error?: string
  // tool.completed result payload (Gateway forwards raw result from claude
  // — typically a string or stringifiable object). Used by SoulHandoffCard
  // to render the worker's reply inside the collapse area.
  result?: unknown
  // claude's tool_use_id — set on both tool.started and tool.completed so
  // chat store can pair them precisely (concurrent tools).
  tool_use_id?: string
  usage?: {
    input_tokens: number
    output_tokens: number
    total_tokens: number
  }
}

function resolveProjectId(body: StartRunRequest): string | null {
  if (body.project_id) return body.project_id
  return localStorage.getItem('hermes_active_profile_id')
}

function resolveSoulId(body: StartRunRequest): string | null {
  return body.soul_id ?? null
}

export async function startRun(body: StartRunRequest): Promise<StartRunResponse> {
  const projectId = resolveProjectId(body)
  if (!projectId) {
    throw new Error('활성 프로젝트가 없습니다. Profiles 메뉴에서 프로젝트를 먼저 등록/선택하세요.')
  }
  const soulId = resolveSoulId(body)
  if (!soulId) {
    throw new Error('Director SOUL이 없습니다. 프로젝트에 Director(Nex) SOUL이 등록되어 있는지 확인하세요.')
  }
  const history = (body.conversation_history ?? [])
    .filter(m => (m.role === 'user' || m.role === 'assistant') && m.content.length > 0)
    .map(m => ({
      role: m.role as 'user' | 'assistant',
      content: typeof m.content === 'string' ? m.content : String(m.content ?? ''),
    }))
    .filter(m => m.content.length > 0)

  const payload: Record<string, unknown> = {
    input: typeof body.input === 'string' ? body.input : JSON.stringify(body.input),
    session_id: body.session_id,
    soul_id: soulId,
    history,
  }
  return request<StartRunResponse>(`/v1/projects/${encodeURIComponent(projectId)}/runs`, {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

// Translate Gateway event payload into Hermes-expected shape.
function translate(eventName: string, raw: Record<string, unknown>): RunEvent {
  switch (eventName) {
    case 'message.delta':
      return { event: 'message.delta', delta: (raw.text as string) || '' }
    case 'tool.started': {
      const toolName = (raw.tool_name as string) || ''
      const input = raw.input
      const preview = input !== undefined ? JSON.stringify(input).slice(0, 140) : undefined
      return {
        event: 'tool.started',
        tool: toolName,
        name: toolName,
        preview,
        // Forward tool_use_id so chat store can pair it with tool.completed.
        tool_use_id: (raw.tool_use_id as string) || undefined,
      }
    }
    case 'tool.completed': {
      const isError = raw.is_error === true
      return {
        event: 'tool.completed',
        // Canonical id-carrying field for tool.completed.
        tool_use_id: (raw.tool_use_id as string) || undefined,
        // Pass through the result payload so the chat store can attach it
        // to the corresponding tool message (used by SoulHandoffCard etc.).
        result: raw.result,
        error: isError ? String(raw.result ?? 'tool error') : undefined,
      }
    }
    case 'run.completed':
      return {
        event: 'run.completed',
        usage: (raw.usage as RunEvent['usage']) ?? undefined,
      }
    case 'run.failed':
      return { event: 'run.failed', error: (raw.reason as string) || 'run failed' }
    case 'session.init':
      return { event: 'session.init' }
    default:
      return { event: eventName, ...raw } as RunEvent
  }
}

export function streamRunEvents(
  runId: string,
  onEvent: (event: RunEvent) => void,
  onDone: () => void,
  onError: (err: Error) => void,
) {
  const baseUrl = getBaseUrlValue()
  const url = `${baseUrl}/v1/runs/${encodeURIComponent(runId)}/events`

  let closed = false
  const source = new EventSource(url)

  const handle = (eventName: string) => (e: MessageEvent) => {
    if (closed) return
    let raw: Record<string, unknown> = {}
    try {
      raw = JSON.parse(e.data)
    } catch {
      // non-JSON payload — keep raw empty
    }
    onEvent(translate(eventName, raw))
    if (eventName === 'run.completed' || eventName === 'run.failed') {
      closed = true
      source.close()
      onDone()
    }
  }

  // Our Gateway emits named events (event: name\ndata: {...}\n\n).
  // EventSource.onmessage only catches default 'message' events, so we must
  // addEventListener for each named event we want.
  source.addEventListener('session.init', handle('session.init'))
  source.addEventListener('message.delta', handle('message.delta'))
  source.addEventListener('tool.started', handle('tool.started'))
  source.addEventListener('tool.completed', handle('tool.completed'))
  source.addEventListener('run.completed', handle('run.completed'))
  source.addEventListener('run.failed', handle('run.failed'))
  // Heartbeats intentionally ignored — no handler needed.

  source.onerror = () => {
    if (closed) return
    closed = true
    source.close()
    onError(new Error('SSE connection error'))
  }

  return {
    abort: () => {
      if (!closed) {
        closed = true
        source.close()
      }
    },
  } as unknown as AbortController
}

// Static model list — Gateway has no /models endpoint.
// TODO(gateway): replace with live endpoint once available.
export async function fetchModels(): Promise<{ data: Array<{ id: string }> }> {
  return {
    data: [
      { id: 'claude-fable-5' },
      { id: 'claude-opus-4-8' },
      { id: 'claude-opus-4-7' },
      { id: 'claude-sonnet-5' },
      { id: 'claude-sonnet-4-6' },
      { id: 'claude-haiku-4-5' },
    ],
  }
}
