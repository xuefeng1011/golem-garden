import { request } from '../client'

export interface Soul {
  id: string
  name: string
  rank: string
  specialty: string[]
  description: string
}

export interface SoulDetail extends Soul {
  content: string
  // N3 fields: capability & isolation metadata
  tools: string[]
  disallowed_tools: string[]
  max_turns: number | null
  isolation: 'none' | 'worktree'
  is_coordinator: boolean
  effort: 'low' | 'medium' | 'high' | null
}

export interface RecentTask {
  task: string
  result: string
  ts: string
}

export interface RankProgress {
  current: string
  next: string | null
  tasks_to_promote: number
}

export interface SoulActivity {
  soul_id: string
  rank: string
  tasks_total: number
  tasks_success: number
  streak: number
  last_task_ts: string
  recent_tasks: RecentTask[]
  rank_progress: RankProgress
}

export async function fetchSouls(projectId: string): Promise<Soul[]> {
  const res = await request<Soul[] | { souls: Soul[] }>(
    `/v1/projects/${encodeURIComponent(projectId)}/souls`
  )
  return Array.isArray(res) ? res : res.souls ?? []
}

export async function fetchSoul(projectId: string, soulId: string): Promise<SoulDetail> {
  return request<SoulDetail>(
    `/v1/projects/${encodeURIComponent(projectId)}/souls/${encodeURIComponent(soulId)}`
  )
}

export async function fetchSoulActivity(
  projectId: string,
  soulId: string,
): Promise<SoulActivity> {
  return request<SoulActivity>(
    `/v1/projects/${encodeURIComponent(projectId)}/souls/${encodeURIComponent(soulId)}/activity`,
  )
}
