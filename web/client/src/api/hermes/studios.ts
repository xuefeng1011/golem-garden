import { request } from '../client'

export interface Studio {
  id: string
  name: string
  path: string
  createdAt: string
  kind: 'studio'
  goal: string
}

// 게이트웨이 원본 payload (snake_case) — missions.ts adaptMission 패턴과 동일하게
// 단일 어댑터 지점에서만 UI 모델로 변환한다.
export interface RawStudio {
  id: string
  name: string
  path: string
  created_at: string
  kind?: string
  goal?: string
}

export function adaptStudio(raw: RawStudio): Studio {
  return {
    id: raw.id,
    name: raw.name,
    path: raw.path,
    createdAt: raw.created_at,
    kind: 'studio',
    goal: raw.goal ?? '',
  }
}

export async function fetchStudios(): Promise<Studio[]> {
  const res = await request<RawStudio[] | { studios: RawStudio[] }>('/v1/studios')
  const list = Array.isArray(res) ? res : res.studios ?? []
  return list.map(adaptStudio)
}

export async function createStudio(name: string, path: string, goal: string): Promise<Studio> {
  const raw = await request<RawStudio>('/v1/studios', {
    method: 'POST',
    body: JSON.stringify({ name, path, goal }),
  })
  return adaptStudio(raw)
}

// 레지스트리 항목만 제거 — 디스크 상의 스튜디오 폴더/산출물은 그대로 남는다 (204 No Content).
export async function deleteStudio(studioId: string): Promise<void> {
  await request<unknown>(`/v1/studios/${encodeURIComponent(studioId)}`, {
    method: 'DELETE',
  })
}

// 엔진-글로벌 팀 프리셋 (프로젝트 스코프 없음) — GET /v1/studio-presets 는 배열을 직접 반환한다.
export interface StudioPreset {
  id: string
  name: string
  description: string
}

export async function fetchStudioPresets(): Promise<StudioPreset[]> {
  return request<StudioPreset[]>('/v1/studio-presets')
}
