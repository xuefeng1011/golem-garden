import { request } from '../client'

export interface FlowStep {
  id: string
  soul: string
  task: string
  deps: string[]
  status: 'pending' | 'waiting_approval' | 'approved' | 'running' | 'done' | 'failed' | 'skipped'
  approval: boolean
  on_fail: string
  run_id?: string | null
  type?: 'input' | 'agent'
  output?: string | null
}

export interface Flow {
  flow_id: string
  goal: string
  status: 'pending' | 'running' | 'paused' | 'completed' | 'failed'
  created: string
  steps: FlowStep[]
}

// Write-only step payload (no status)
export interface WriteStep {
  id: string
  soul: string
  task: string
  deps: string[]
  retry: number
  approval: boolean
  on_fail: string
  type?: 'input' | 'agent'
}

export interface CreateFlowPayload {
  goal: string
  steps: WriteStep[]
}

export async function fetchFlows(projectId: string, limit = 20): Promise<Flow[]> {
  return request<Flow[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/flows?limit=${limit}`,
  )
}

// 단건 조회 — 실행 중 1.5초 폴링 전용 (목록 전체 파싱 O(n) → O(1))
export async function fetchFlow(projectId: string, flowId: string): Promise<Flow> {
  return request<Flow>(
    `/v1/projects/${encodeURIComponent(projectId)}/flows/${encodeURIComponent(flowId)}`,
  )
}

export async function createFlow(
  projectId: string,
  payload: CreateFlowPayload,
): Promise<{ flow_id: string }> {
  return request<{ flow_id: string }>(
    `/v1/projects/${encodeURIComponent(projectId)}/flows`,
    { method: 'POST', body: JSON.stringify(payload) },
  )
}

export async function updateFlow(
  projectId: string,
  flowId: string,
  payload: CreateFlowPayload,
): Promise<void> {
  await request<unknown>(
    `/v1/projects/${encodeURIComponent(projectId)}/flows/${encodeURIComponent(flowId)}`,
    { method: 'PUT', body: JSON.stringify(payload) },
  )
}

export async function deleteFlow(
  projectId: string,
  flowId: string,
): Promise<void> {
  await request<unknown>(
    `/v1/projects/${encodeURIComponent(projectId)}/flows/${encodeURIComponent(flowId)}`,
    { method: 'DELETE' },
  )
}
