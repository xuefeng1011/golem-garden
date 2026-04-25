import { request } from '../client'

// Our Gateway "Project" shape
interface GatewayProject {
  id: string
  name: string
  path: string
  [key: string]: unknown
}

// Hermes-compatible Profile shape (preserved so existing views keep working)
export interface HermesProfile {
  name: string
  active: boolean
  model: string
  gateway: string
  alias: string
  // Gateway extras surfaced for project-centric flows
  id?: string
  path?: string
}

export interface HermesProfileDetail {
  name: string
  path: string
  model: string
  provider: string
  gateway: string
  skills: number
  hasEnv: boolean
  hasSoulMd: boolean
  id?: string
}

function projectToProfile(p: GatewayProject): HermesProfile {
  return {
    name: p.name,
    active: false,
    model: '',
    gateway: '',
    alias: p.id,
    id: p.id,
    path: p.path,
  }
}

function projectToDetail(p: GatewayProject): HermesProfileDetail {
  return {
    name: p.name,
    path: p.path,
    model: '',
    provider: '',
    gateway: '',
    skills: 0,
    hasEnv: false,
    hasSoulMd: false,
    id: p.id,
  }
}

export async function fetchProfiles(): Promise<HermesProfile[]> {
  const res = await request<GatewayProject[] | { projects: GatewayProject[] }>('/v1/projects')
  const list = Array.isArray(res) ? res : res.projects ?? []
  return list.map(projectToProfile)
}

export async function fetchProfileDetail(idOrName: string): Promise<HermesProfileDetail> {
  const res = await request<GatewayProject[] | { projects: GatewayProject[] }>('/v1/projects')
  const list = Array.isArray(res) ? res : res.projects ?? []
  const match = list.find((p) => p.id === idOrName || p.name === idOrName)
  if (!match) throw new Error(`Project not found: ${idOrName}`)
  return projectToDetail(match)
}

// Gateway signature: POST /v1/projects with body { name, path }.
// Second arg is `path?` in Gateway terms; legacy Hermes called with a bool
// (clone). When a boolean is passed we ignore it and use name as path.
export async function createProfile(name: string, pathOrClone?: string | boolean): Promise<boolean> {
  try {
    const path = typeof pathOrClone === 'string' ? pathOrClone : name
    await request('/v1/projects', {
      method: 'POST',
      body: JSON.stringify({ name, path }),
    })
    return true
  } catch {
    return false
  }
}

export async function deleteProfile(idOrName: string): Promise<boolean> {
  try {
    // Resolve to id if a name was passed
    const list = await fetchProfiles()
    const match = list.find((p) => p.id === idOrName || p.name === idOrName)
    const id = match?.id ?? idOrName
    await request(`/v1/projects/${encodeURIComponent(id)}`, { method: 'DELETE' })
    return true
  } catch {
    return false
  }
}

// TODO(gateway): rename/switch/export/import — Gateway has no counterparts yet.
export async function renameProfile(_name: string, _newName: string): Promise<boolean> {
  return false
}

export async function switchProfile(_name: string): Promise<boolean> {
  // "Active profile" is tracked client-side only (Pinia).
  return true
}

export async function exportProfile(_name: string): Promise<boolean> {
  return false
}

export async function importProfile(_file: File): Promise<boolean> {
  return false
}
