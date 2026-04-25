// Stub — Gateway has no session persistence endpoints.
// Chat store calls fetchSessions/fetchSession/etc; we return empty data so
// the UI renders cleanly.
// TODO(gateway): wire up real session endpoints once Gateway exposes them.

export interface SessionSummary {
  id: string
  source: string
  model: string
  title: string | null
  preview?: string
  started_at: number
  ended_at: number | null
  last_active?: number
  message_count: number
  tool_call_count: number
  input_tokens: number
  output_tokens: number
  cache_read_tokens: number
  cache_write_tokens: number
  reasoning_tokens: number
  billing_provider: string | null
  estimated_cost_usd: number
  actual_cost_usd: number | null
  cost_status: string
}

export interface SessionDetail extends SessionSummary {
  messages: HermesMessage[]
}

export interface SessionSearchResult extends SessionSummary {
  matched_message_id: number | null
  snippet: string
  rank: number
}

export interface HermesMessage {
  id: number
  session_id: string
  role: 'user' | 'assistant' | 'system' | 'tool'
  content: string
  tool_call_id: string | null
  tool_calls: any[] | null
  tool_name: string | null
  timestamp: number
  token_count: number | null
  finish_reason: string | null
  reasoning: string | null
}

export async function fetchSessions(_source?: string, _limit?: number): Promise<SessionSummary[]> {
  return []
}

export async function searchSessions(_q: string, _source?: string, _limit?: number): Promise<SessionSearchResult[]> {
  return []
}

export async function fetchSession(_id: string): Promise<SessionDetail | null> {
  return null
}

export async function deleteSession(_id: string): Promise<boolean> {
  return false
}

export async function renameSession(_id: string, _title: string): Promise<boolean> {
  return false
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
