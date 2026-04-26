import { request } from '../client'

export interface ActiveSoul {
  id: string
  name: string
  rank: string
}

export interface ActivityEntry {
  soul: string
  task: string
  result: string
  ts: string
}

export interface ProjectOverview {
  project_id: string
  name: string
  souls_count: number
  active_souls: ActiveSoul[]
  recent_activity: ActivityEntry[]
  total_tasks: number
  success_rate: number
  total_cost_usd: number
  last_activity_ts: string
}

export interface BoardTeamMember {
  name: string
  soul?: string
  role: string
  rank: string
  agent?: string
  model?: string
  status?: string
}

export interface TechDebtItem {
  text: string
  resolved: boolean
}

export interface HistoryEntry {
  date: string
  task: string
  soul: string
  result: string
}

export interface ProjectBoard {
  raw_md: string
  team: BoardTeamMember[]
  tech_debt: TechDebtItem[]
  history: HistoryEntry[]
}

export async function fetchOverview(projectId: string): Promise<ProjectOverview> {
  return request<ProjectOverview>(
    `/v1/projects/${encodeURIComponent(projectId)}/overview`
  )
}

export async function fetchBoard(projectId: string): Promise<ProjectBoard> {
  return request<ProjectBoard>(
    `/v1/projects/${encodeURIComponent(projectId)}/board`
  )
}
