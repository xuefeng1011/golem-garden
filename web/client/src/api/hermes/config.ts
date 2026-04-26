// Stub — Gateway has no config endpoints.
// TODO(gateway): wire up real endpoints once Gateway exposes them.

export interface DisplayConfig {
  compact?: boolean
  personality?: string
  resume_display?: string
  busy_input_mode?: string
  bell_on_complete?: boolean
  show_reasoning?: boolean
  streaming?: boolean
  inline_diffs?: boolean
  show_cost?: boolean
  skin?: string
}

export interface AgentConfig {
  max_turns?: number
  gateway_timeout?: number
  restart_drain_timeout?: number
  service_tier?: string
  tool_use_enforcement?: string
}

export interface MemoryConfig {
  memory_enabled?: boolean
  user_profile_enabled?: boolean
  memory_char_limit?: number
  user_char_limit?: number
}

export interface SessionResetConfig {
  mode?: string
  idle_minutes?: number
  at_hour?: number
}

export interface PrivacyConfig {
  redact_pii?: boolean
}

export interface AppConfig {
  display?: DisplayConfig
  agent?: AgentConfig
  memory?: MemoryConfig
  session_reset?: SessionResetConfig
  privacy?: PrivacyConfig
  telegram?: Record<string, any>
  discord?: Record<string, any>
  slack?: Record<string, any>
  whatsapp?: Record<string, any>
  matrix?: Record<string, any>
  weixin?: Record<string, any>
  wecom?: Record<string, any>
  feishu?: Record<string, any>
  dingtalk?: Record<string, any>
  platforms?: Record<string, any>
  [key: string]: any
}

export async function fetchConfig(_sections?: string[]): Promise<AppConfig> {
  return {}
}

export async function updateConfigSection(
  _section: string,
  _values: Record<string, any>,
): Promise<void> {
  // no-op
}

export async function saveCredentials(
  _platform: string,
  _values: Record<string, any>,
): Promise<void> {
  // no-op
}

export interface WeixinQrCode {
  qrcode: string
  qrcode_url: string
}

export interface WeixinQrStatus {
  status: 'wait' | 'scaned' | 'scaned_but_redirect' | 'expired' | 'confirmed'
  account_id?: string
  token?: string
  base_url?: string
}

export async function fetchWeixinQrCode(): Promise<WeixinQrCode> {
  return { qrcode: '', qrcode_url: '' }
}

export async function pollWeixinQrStatus(_qrcode: string): Promise<WeixinQrStatus> {
  return { status: 'wait' }
}

export async function saveWeixinCredentials(_data: {
  account_id: string
  token: string
  base_url?: string
}): Promise<void> {
  // no-op
}
