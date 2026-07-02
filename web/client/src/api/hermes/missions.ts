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

// bash 엔진(state.json)이 소스 오브 트루스 — mission: active/completed,
// task: pending/in_progress/done/failed. UI enum 과의 정합은 이 어댑터
// 한 곳에서만 처리한다 (기존엔 bash 가 절대 만들지 않는 running/error 를
// 타입이 주장해 상태 pill 이 매칭 실패하던 부정합).
export type RawMission = Omit<Mission, 'status' | 'tasks'> & {
  status: string
  tasks: Array<Omit<MissionTask, 'status'> & { status: string }>
}

function mapTaskStatus(raw: string): MissionTask['status'] {
  if (raw === 'failed') return 'error'
  if (raw === 'pending' || raw === 'in_progress' || raw === 'done') return raw
  return 'pending'
}

function mapMissionStatus(raw: string): Mission['status'] {
  if (raw === 'active') return 'running'
  if (raw === 'completed' || raw === 'failed') return raw
  return 'pending'
}

export function adaptMission(raw: RawMission): Mission {
  return {
    ...raw,
    status: mapMissionStatus(raw.status),
    tasks: raw.tasks.map((t) => ({ ...t, status: mapTaskStatus(t.status) })),
  }
}

export async function fetchMissions(
  projectId: string,
  limit = 20,
): Promise<Mission[]> {
  const raw = await request<RawMission[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/missions?limit=${limit}`,
  )
  return raw.map(adaptMission)
}

export async function fetchMission(
  projectId: string,
  missionId: string,
): Promise<Mission> {
  const raw = await request<RawMission>(
    `/v1/projects/${encodeURIComponent(projectId)}/missions/${encodeURIComponent(missionId)}`,
  )
  return adaptMission(raw)
}

/**
 * 결정론 미션 루프(forge mission run) 시작 — 반환된 run_id 로
 * 기존 forge-runs SSE(GET /v1/forge-runs/{id}/events)를 구독하고,
 * 중지는 DELETE /v1/forge-runs/{id} 를 그대로 재사용한다.
 */
export async function runMission(
  projectId: string,
  missionId: string,
  opts: { soul?: string; verifier?: string } = {},
): Promise<{ run_id: string }> {
  return request<{ run_id: string }>(
    `/v1/projects/${encodeURIComponent(projectId)}/missions/${encodeURIComponent(missionId)}/run`,
    {
      method: 'POST',
      body: JSON.stringify({ soul: opts.soul ?? '', verifier: opts.verifier ?? '' }),
    },
  )
}
