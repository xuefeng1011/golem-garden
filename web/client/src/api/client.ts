const DEFAULT_BASE_URL = 'http://127.0.0.1:8642'

function getBaseUrl(): string {
  return localStorage.getItem('hermes_server_url') || DEFAULT_BASE_URL
}

// Auth stubs — Gateway has no auth. Kept as no-ops for any legacy callers.
export function getApiKey(): string {
  return ''
}

export function setServerUrl(url: string) {
  localStorage.setItem('hermes_server_url', url)
}

export function setApiKey(_key: string) {
  // no-op: Gateway has no auth
}

export function clearApiKey() {
  // no-op
}

export function hasApiKey(): boolean {
  return true
}

export async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const base = getBaseUrl()
  const url = `${base}${path}`
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...options.headers as Record<string, string>,
  }

  const res = await fetch(url, { ...options, headers })

  if (!res.ok) {
    const text = await res.text().catch(() => '')
    throw new Error(`API Error ${res.status}: ${text || res.statusText}`)
  }

  return res.json()
}

export function getBaseUrlValue(): string {
  return getBaseUrl()
}
