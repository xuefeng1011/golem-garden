// Stub — Gateway has no logs endpoints.
// TODO(gateway): wire up real endpoints once Gateway exposes them.

export interface LogFileInfo {
  name: string
  size: string
  modified: string
}

export interface LogEntry {
  timestamp: string
  level: string
  logger: string
  message: string
  raw: string
}

export async function fetchLogFiles(): Promise<LogFileInfo[]> {
  return []
}

export async function fetchLogs(_name: string, _params?: {
  lines?: number
  level?: string
  session?: string
  since?: string
}): Promise<LogEntry[]> {
  return []
}
