import { request } from '../client'

export interface FlowStep {
  id: string
  soul: string
  task: string
  deps: string[]
  status: 'pending' | 'waiting_approval' | 'approved' | 'running' | 'done' | 'failed' | 'skipped'
  approval: boolean
  on_fail: string
}

export interface Flow {
  flow_id: string
  goal: string
  status: 'pending' | 'running' | 'paused' | 'completed' | 'failed'
  created: string
  steps: FlowStep[]
}

export async function fetchFlows(projectId: string, limit = 20): Promise<Flow[]> {
  return request<Flow[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/flows?limit=${limit}`,
  )
}
