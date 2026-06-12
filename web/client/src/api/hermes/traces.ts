import { request } from '../client'
import type { RunMeta } from './console'

export type { RunMeta }

export interface TraceResponse {
  run_id: string
  total_lines: number
  offset: number
  lines: object[]
}

export async function fetchRuns(
  projectId: string,
  limit = 50,
  offset = 0
): Promise<RunMeta[]> {
  return request<RunMeta[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/runs?limit=${limit}&offset=${offset}`
  )
}

export async function fetchTrace(
  projectId: string,
  runId: string,
  offset = 0,
  limit = 200
): Promise<TraceResponse> {
  return request<TraceResponse>(
    `/v1/projects/${encodeURIComponent(projectId)}/runs/${encodeURIComponent(runId)}/trace?offset=${offset}&limit=${limit}`
  )
}
