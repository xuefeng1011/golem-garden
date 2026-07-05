// Stub — Gateway has no system/config/models endpoints yet.
// All functions return neutral defaults or no-op.
// TODO(gateway): wire up real endpoints once Gateway exposes them.
import { request } from '../client'

export interface HealthResponse {
  status: string
  version?: string
  webui_version?: string
  webui_latest?: string
  webui_update_available?: boolean
  node_version?: string
}

export interface ModelInfo {
  id: string
  label: string
}

export interface ModelGroup {
  provider: string
  models: ModelInfo[]
}

export interface ConfigModelsResponse {
  default: string
  groups: ModelGroup[]
}

export interface AvailableModelGroup {
  provider: string
  label: string
  base_url: string
  models: string[]
  api_key: string
}

export interface AvailableModelsResponse {
  default: string
  default_provider: string
  groups: AvailableModelGroup[]
  allProviders: AvailableModelGroup[]
}

export interface CustomProvider {
  name: string
  base_url: string
  api_key: string
  model: string
  context_length?: number
  providerKey?: string | null
}

export async function checkHealth(): Promise<HealthResponse> {
  try {
    return await request<HealthResponse>('/health')
  } catch {
    return { status: 'unknown' }
  }
}

export async function triggerUpdate(): Promise<{ success: boolean; message: string }> {
  return { success: false, message: 'Not supported by Gateway' }
}

export async function fetchConfigModels(): Promise<ConfigModelsResponse> {
  return {
    default: 'claude-opus-4-8',
    groups: [
      {
        provider: 'anthropic',
        models: [
          { id: 'claude-fable-5', label: 'Claude Fable 5' },
          { id: 'claude-opus-4-8', label: 'Claude Opus 4.8' },
          { id: 'claude-opus-4-7', label: 'Claude Opus 4.7' },
          { id: 'claude-sonnet-5', label: 'Claude Sonnet 5' },
          { id: 'claude-sonnet-4-6', label: 'Claude Sonnet 4.6' },
          { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5' },
        ],
      },
    ],
  }
}

export async function fetchAvailableModels(): Promise<AvailableModelsResponse> {
  return {
    default: 'claude-opus-4-8',
    default_provider: 'anthropic',
    groups: [],
    allProviders: [],
  }
}

export async function updateDefaultModel(_data: {
  default: string
  provider?: string
  base_url?: string
  api_key?: string
}): Promise<void> {
  // no-op
}

export async function addCustomProvider(_data: CustomProvider): Promise<void> {
  // no-op
}

export async function removeCustomProvider(_name: string): Promise<void> {
  // no-op
}

export async function updateProvider(_poolKey: string, _data: {
  name?: string
  base_url?: string
  api_key?: string
  model?: string
}): Promise<void> {
  // no-op
}
