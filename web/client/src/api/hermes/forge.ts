import { request, getBaseUrlValue } from '../client'

export interface StartForgeRequest {
  command: string
  args: string[]
}

export interface StartForgeResponse {
  run_id: string
}

export interface ForgeEvent {
  event: 'forge.stdout' | 'forge.stderr' | 'forge.completed' | 'forge.failed' | 'heartbeat'
  line?: string
  exit_code?: number | null
  duration_ms?: number
  reason?: string
}

export interface ForgeCompletedEvent {
  exit_code: number
  duration_ms: number
}

export interface ForgeFailedEvent {
  exit_code: number | null
  duration_ms: number
  reason: string
}

export async function startForge(
  projectId: string,
  command: string,
  args: string[],
): Promise<StartForgeResponse> {
  return request<StartForgeResponse>(
    `/v1/projects/${encodeURIComponent(projectId)}/forge`,
    {
      method: 'POST',
      body: JSON.stringify({ command, args }),
    },
  )
}

export function streamForgeEvents(
  runId: string,
  onEvent: (event: ForgeEvent) => void,
  onDone: (result: ForgeCompletedEvent | ForgeFailedEvent) => void,
  onError: (err: Error) => void,
): { abort: () => void } {
  const baseUrl = getBaseUrlValue()
  const url = `${baseUrl}/v1/forge-runs/${encodeURIComponent(runId)}/events`

  let closed = false
  const source = new EventSource(url)

  const handleTerminal = (eventName: 'forge.completed' | 'forge.failed') => (e: MessageEvent) => {
    if (closed) return
    let raw: Record<string, unknown> = {}
    try {
      raw = JSON.parse(e.data)
    } catch {
      // ignore parse errors
    }
    onEvent({ event: eventName, ...raw } as ForgeEvent)
    closed = true
    source.close()
    if (eventName === 'forge.completed') {
      onDone({ exit_code: raw.exit_code as number, duration_ms: raw.duration_ms as number })
    } else {
      onDone({
        exit_code: (raw.exit_code as number | null) ?? null,
        duration_ms: raw.duration_ms as number,
        reason: (raw.reason as string) ?? 'unknown',
      })
    }
  }

  const handleLine = (eventName: 'forge.stdout' | 'forge.stderr') => (e: MessageEvent) => {
    if (closed) return
    let raw: Record<string, unknown> = {}
    try {
      raw = JSON.parse(e.data)
    } catch {
      // ignore
    }
    onEvent({ event: eventName, line: (raw.line as string) ?? '' })
  }

  source.addEventListener('forge.stdout', handleLine('forge.stdout'))
  source.addEventListener('forge.stderr', handleLine('forge.stderr'))
  source.addEventListener('forge.completed', handleTerminal('forge.completed'))
  source.addEventListener('forge.failed', handleTerminal('forge.failed'))
  // heartbeat intentionally ignored

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
  }
}
