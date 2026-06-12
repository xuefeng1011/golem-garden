/**
 * Markdown heading outline extractor.
 *
 * Pure function: extracts `#`/`##`/`###` headings from a markdown string so
 * the chat UI can build a navigation outline for long assistant responses.
 * Headings inside fenced code blocks (``` ... ```) are excluded by tracking
 * fence open/close toggles, mirroring the convention in fence-repair.ts
 * (line-start fence, up to 3 leading spaces).
 */

export interface OutlineItem {
  /** Heading depth: 1 (`#`), 2 (`##`), or 3 (`###`). */
  level: number
  /** Heading text with markers stripped and whitespace trimmed. */
  text: string
  /** Collision-free id: message id + heading index within that message. */
  anchorId: string
  /** Owning message id (for DOM lookup of the message container). */
  messageId: string
  /** Zero-based index among this message's h1–h3 headings (DOM order). */
  headingIndex: number
}

// Fence delimiter at line start (up to 3 leading spaces), backtick or tilde.
const FENCE_RE = /^ {0,3}(`{3,}|~{3,})/
// ATX heading: 1–3 hashes followed by at least one space, then text.
const HEADING_RE = /^(#{1,3})\s+(.+?)\s*$/

export function extractOutline(markdown: string, messageId: string): OutlineItem[] {
  if (!markdown) return []

  const items: OutlineItem[] = []
  let inFence = false
  let headingIndex = 0

  for (const line of markdown.split('\n')) {
    if (FENCE_RE.test(line)) {
      inFence = !inFence
      continue
    }
    if (inFence) continue

    const match = HEADING_RE.exec(line)
    if (!match) continue

    // Strip an optional closing hash sequence ("## Title ##" -> "Title").
    const text = match[2].replace(/\s+#+$/, '').trim()
    if (!text) continue

    items.push({
      level: match[1].length,
      text,
      anchorId: `outline-${messageId}-${headingIndex}`,
      messageId,
      headingIndex,
    })
    headingIndex += 1
  }

  return items
}
