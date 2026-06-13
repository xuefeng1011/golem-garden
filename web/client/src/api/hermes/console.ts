import { request } from '../client'
import type { ProjectBudget } from './budget'

export interface ActiveRun {
  run_id: string
  session_id: string
  soul: string
  elapsed_ms: number
}

export interface ConsoleStats {
  total_runs: number
  success: number
  error: number
  timeout: number
  success_rate: number // 0..1 비율 (표시 시 ×100)
  avg_duration_ms: number
  total_cost_usd: number
  total_tokens_out: number
  // 프롬프트 캐시 적중률 0..1 — 분리 키 가진 런이 없으면 null
  cache_hit_rate: number | null
}

export interface BySoulEntry {
  soul: string
  runs: number
  cost_usd: number
  success_rate: number
}

export interface RunMeta {
  run_id: string
  session_id: string
  soul: string
  model: string
  source: string
  ts_start: string
  duration_ms: number
  tokens_in: number
  tokens_out: number
  tokens_cache: number
  cost_usd: number
  result: 'success' | 'error' | 'timeout'
  tool_counts: Record<string, number>
}

export interface ConsoleData {
  active_runs: ActiveRun[]
  stats: ConsoleStats
  by_soul: BySoulEntry[]
  recent_runs: RunMeta[]
  budget: ProjectBudget
}

export async function fetchConsole(projectId: string): Promise<ConsoleData> {
  return request<ConsoleData>(
    `/v1/projects/${encodeURIComponent(projectId)}/console`
  )
}
