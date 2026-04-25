import { request } from '../client'

// ── New Gateway-backed types ──────────────────────────────────────────────────

export interface Skill {
  id: string
  name: string
  description: string
}

export interface SkillDetail extends Skill {
  content: string
  has_scripts: boolean
}

export async function fetchSkills(projectId: string): Promise<Skill[]> {
  const res = await request<Skill[] | { skills: Skill[] }>(
    `/v1/projects/${encodeURIComponent(projectId)}/skills`,
  )
  return Array.isArray(res) ? res : res.skills ?? []
}

export async function fetchSkill(projectId: string, skillId: string): Promise<SkillDetail> {
  return request<SkillDetail>(
    `/v1/projects/${encodeURIComponent(projectId)}/skills/${encodeURIComponent(skillId)}`,
  )
}

export async function fetchGlobalSkills(): Promise<Skill[]> {
  const res = await request<Skill[] | { skills: Skill[] }>('/v1/skills/global')
  return Array.isArray(res) ? res : res.skills ?? []
}

export async function fetchGlobalSkill(skillId: string): Promise<SkillDetail> {
  return request<SkillDetail>(`/v1/skills/global/${encodeURIComponent(skillId)}`)
}

// ── Legacy stub types (kept so existing imports don't break) ──────────────────

export interface SkillInfo {
  name: string
  description: string
  enabled?: boolean
}

export interface SkillCategory {
  name: string
  description: string
  skills: SkillInfo[]
}

export interface SkillListResponse {
  categories: SkillCategory[]
}

export interface SkillFileEntry {
  path: string
  name: string
  isDir: boolean
}

export interface MemoryData {
  memory: string
  user: string
  soul: string
  memory_mtime: number | null
  user_mtime: number | null
  soul_mtime: number | null
}

export async function fetchSkillContent(_skillPath: string): Promise<string> {
  return ''
}

export async function fetchSkillFiles(
  _category: string,
  _skill: string,
): Promise<SkillFileEntry[]> {
  return []
}

export async function fetchMemory(): Promise<MemoryData> {
  return {
    memory: '',
    user: '',
    soul: '',
    memory_mtime: null,
    user_mtime: null,
    soul_mtime: null,
  }
}

export async function saveMemory(
  _section: 'memory' | 'user' | 'soul',
  _content: string,
): Promise<void> {
  // no-op
}

export async function toggleSkill(_name: string, _enabled: boolean): Promise<void> {
  // no-op
}
