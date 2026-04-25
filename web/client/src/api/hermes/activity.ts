import { request } from '../client'

export type TimelineEventType = 'task' | 'session_start' | 'session_end' | 'mailbox'

export interface TaskDetails {
  result?: string
  cost_usd?: number
  tokens?: number
}

export interface SessionDetails {
  souls?: string[]
  reason?: string
}

export interface MailboxDetails {
  to?: string
  msg_type?: string
  content?: string
}

export interface TimelineEvent {
  type: TimelineEventType
  soul: string
  ts: string
  summary: string
  details?: TaskDetails | SessionDetails | MailboxDetails
}

export async function fetchTimeline(projectId: string, limit = 50): Promise<TimelineEvent[]> {
  return request<TimelineEvent[]>(
    `/v1/projects/${encodeURIComponent(projectId)}/timeline?limit=${limit}`
  )
}
