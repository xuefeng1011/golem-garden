import { request } from '../client'

export interface Achievement {
  id: string
  soul: string
  badge: string
  description: string
  earned_at: string
}

export interface ChemistryPair {
  souls: [string, string]
  score: number | null
  interactions: number
}

export interface ChemistryEvent {
  souls: [string, string]
  event: string
  ts: string
}

export interface ChemistryData {
  pairs: ChemistryPair[]
  raw_events: ChemistryEvent[]
}

export async function fetchAchievements(projectId: string): Promise<Achievement[]> {
  const res = await request<Achievement[] | { achievements: Achievement[] }>(
    `/v1/projects/${encodeURIComponent(projectId)}/achievements`
  )
  return Array.isArray(res) ? res : res.achievements ?? []
}

export async function fetchChemistry(projectId: string): Promise<ChemistryData> {
  return request<ChemistryData>(
    `/v1/projects/${encodeURIComponent(projectId)}/chemistry`
  )
}
