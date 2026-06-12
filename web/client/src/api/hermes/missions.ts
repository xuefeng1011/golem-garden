import { request } from '../client'

export interface MissionTask {
  idx: number
  task: string
  soul: string
  status: 'pending' | 'in_progress' | 'done' | 'error'
}

export interface Mission {
  id: string
  goal: string
  status: 'running' | 'completed' | 'failed' | 'pending'
  created: string
  tasks: MissionTask[]
}

export async function fetchMissions(
  projectId: string,
  limit = 20,
): Promise<Mission[]> {
  return request<Mission[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/missions?limit=${limit}`,
  )
}
