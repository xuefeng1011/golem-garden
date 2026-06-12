// Client-side session export helpers — zero dependencies.
// Pure functions (slug/filename/markdown) are separated from the DOM
// download trigger so they can be unit-tested in isolation.

import type { SessionDetail, HermesMessage } from '@/api/hermes/sessions'

/**
 * Slugify a session title for use in a filename.
 * Keeps unicode letters/digits (Korean titles stay readable),
 * collapses everything else into single hyphens.
 */
export function slugifyTitle(title: string): string {
  const slug = (title || '')
    .normalize('NFC')
    .replace(/[^\p{L}\p{N}]+/gu, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase()
    .slice(0, 60)
    .replace(/-+$/, '')
  return slug || 'session'
}

/** Build `{slug}_{YYYY-MM-DD}.{ext}` from a title and a date. */
export function buildExportFilename(title: string, ext: 'json' | 'md', date: Date = new Date()): string {
  const yyyy = date.getFullYear()
  const mm = String(date.getMonth() + 1).padStart(2, '0')
  const dd = String(date.getDate()).padStart(2, '0')
  return `${slugifyTitle(title)}_${yyyy}-${mm}-${dd}.${ext}`
}

function roleHeading(msg: HermesMessage): string {
  switch (msg.role) {
    case 'user': return 'User'
    case 'assistant': return 'Assistant'
    case 'system': return 'System'
    case 'tool': return msg.tool_name ? `Tool (${msg.tool_name})` : 'Tool'
    default: return String(msg.role)
  }
}

/**
 * Convert a Gateway session detail into a Markdown transcript:
 * a title header, light metadata, then one `## {Role}` section per message.
 */
export function sessionToMarkdown(detail: SessionDetail): string {
  const lines: string[] = []
  lines.push(`# ${detail.title || 'Untitled session'}`)
  lines.push('')
  const meta: string[] = []
  if (detail.id) meta.push(`- Session: \`${detail.id}\``)
  if (detail.soul_id) meta.push(`- SOUL: ${detail.soul_id}`)
  if (detail.model) meta.push(`- Model: ${detail.model}`)
  if (detail.created_at) meta.push(`- Created: ${detail.created_at}`)
  if (meta.length) {
    lines.push(...meta)
    lines.push('')
  }
  for (const msg of detail.messages || []) {
    lines.push(`## ${roleHeading(msg)}`)
    lines.push('')
    lines.push((msg.content ?? '').trimEnd())
    lines.push('')
  }
  return lines.join('\n').trimEnd() + '\n'
}

/** Trigger a client-side file download via Blob + a[download]. */
export function triggerDownload(filename: string, content: string, mimeType: string): void {
  const blob = new Blob([content], { type: mimeType })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}
