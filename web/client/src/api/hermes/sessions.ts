// Gateway session persistence endpoints.
// All session data is stored in SQLite per-project on the Gateway.
//
// Endpoints:
//   GET    /v1/projects/{project_id}/sessions?limit=100
//   GET    /v1/projects/{project_id}/sessions/{session_id}
//   DELETE /v1/projects/{project_id}/sessions/{session_id}

import { request, getBaseUrlValue } from '../client'

// ── Gateway response shapes ────────────────────────────────────────────────

export interface SessionSummary {
  id: string
  soul_id: string | null
  title: string
  created_at: string
  updated_at: string
  message_count: number
}

export interface HermesMessage {
  id: number
  session_id?: string
  role: 'user' | 'assistant' | 'system' | 'tool'
  content: string
  soul_id?: string | null
  tool_name: string | null
  // Gateway stores created_at as ISO string; fallback: timestamp as Unix seconds
  created_at?: string
  timestamp?: number
  // Optional fields carried over from old Hermes shape (may be absent)
  tool_call_id?: string | null
  tool_calls?: any[] | null
  token_count?: number | null
  finish_reason?: string | null
  reasoning?: string | null
}

export interface SessionDetail extends SessionSummary {
  messages: HermesMessage[]
}

// ── Legacy-compat stubs for shapes the store/views reference ──────────────
// These are never populated from the Gateway but kept so TypeScript
// callers that import the types don't break.
export interface SessionSearchResult extends SessionSummary {
  matched_message_id: number | null
  snippet: string
  rank: number
}

// ── Helpers ────────────────────────────────────────────────────────────────

function getProjectId(): string | null {
  return localStorage.getItem('hermes_active_profile_id')
}

// ── API functions ──────────────────────────────────────────────────────────

export async function fetchSessions(
  projectId?: string | null,
  _limit?: number,
): Promise<SessionSummary[]> {
  const pid = projectId ?? getProjectId()
  if (!pid) return []
  try {
    return await request<SessionSummary[]>(`/v1/projects/${pid}/sessions?limit=100`)
  } catch (err) {
    console.error('fetchSessions error:', err)
    return []
  }
}

export async function fetchSession(
  id: string,
  projectId?: string | null,
): Promise<SessionDetail | null> {
  const pid = projectId ?? getProjectId()
  if (!pid) return null
  try {
    return await request<SessionDetail>(`/v1/projects/${pid}/sessions/${id}`)
  } catch (err) {
    console.error('fetchSession error:', err)
    return null
  }
}

export async function deleteSession(
  id: string,
  projectId?: string | null,
): Promise<boolean> {
  const pid = projectId ?? getProjectId()
  if (!pid) return false
  try {
    const res = await fetch(
      `${getBaseUrlValue()}/v1/projects/${pid}/sessions/${id}`,
      { method: 'DELETE' },
    )
    return res.status === 204 || res.status === 200
  } catch (err) {
    console.error('deleteSession error:', err)
    return false
  }
}

export async function renameSession(_id: string, _title: string): Promise<boolean> {
  // Gateway has no rename endpoint yet — kept as no-op so ChatPanel compiles.
  return false
}

// ── Stub-only exports (no Gateway backing) ────────────────────────────────
// These were part of the old Hermes API. Kept as no-ops so any remaining
// import sites don't break.

export async function searchSessions(
  _q: string,
  _source?: string,
  _limit?: number,
): Promise<SessionSearchResult[]> {
  return []
}

export async function fetchSessionUsage(
  _ids: string[],
): Promise<Record<string, { input_tokens: number; output_tokens: number }>> {
  return {}
}

export async function fetchSessionUsageSingle(
  _id: string,
): Promise<{ input_tokens: number; output_tokens: number } | null> {
  return null
}

export async function fetchContextLength(_profile?: string): Promise<number> {
  return 200000
}
