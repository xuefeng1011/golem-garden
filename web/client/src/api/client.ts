import { ApiError, classifyHttpStatus } from '@/utils/api-error'

export { ApiError } from '@/utils/api-error'

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

  let res: Response
  try {
    res = await fetch(url, { ...options, headers })
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    throw new ApiError(`API Error network: ${msg}`, null, 'network')
  }

  if (!res.ok) {
    const text = await res.text().catch(() => '')
    const kind = classifyHttpStatus(res.status)
    throw new ApiError(`API Error ${res.status}: ${text || res.statusText}`, res.status, kind)
  }

  // 204 No Content (and any other empty body) has nothing for res.json() to parse —
  // parsing an empty string throws a SyntaxError. Callers expecting void (DELETE etc.)
  // get undefined instead.
  if (res.status === 204 || res.headers.get('content-length') === '0') {
    return undefined as T
  }

  return res.json()
}

export function getBaseUrlValue(): string {
  return getBaseUrl()
}
