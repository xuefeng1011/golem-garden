import { request } from '../client'

export interface Artifact {
  path: string
  name: string
  size: number
  mtime: string
}

export interface ArtifactContent {
  path: string
  content: string
  truncated: boolean
  binary: boolean
  size: number
}

// 게이트웨이 원본 payload — studios.ts/missions.ts 어댑터 패턴과 동일하게 단일
// 변환 지점을 유지한다. 현재 계약은 이미 camelCase 필드지만, 게이트웨이가
// snake_case로 바뀌어도 이 지점만 고치면 되도록 어댑터를 분리해 둔다.
export interface RawArtifact {
  path: string
  name: string
  size: number
  mtime: string
}

export function adaptArtifact(raw: RawArtifact): Artifact {
  return {
    path: raw.path,
    name: raw.name,
    size: raw.size,
    mtime: raw.mtime,
  }
}

export async function fetchArtifacts(projectId: string, dir = 'output'): Promise<Artifact[]> {
  const raw = await request<RawArtifact[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/artifacts?dir=${encodeURIComponent(dir)}`,
  )
  return raw.map(adaptArtifact)
}

export async function fetchArtifactContent(
  projectId: string,
  path: string,
): Promise<ArtifactContent> {
  return request<ArtifactContent>(
    `/v1/projects/${encodeURIComponent(projectId)}/artifacts/content?path=${encodeURIComponent(path)}`,
  )
}
