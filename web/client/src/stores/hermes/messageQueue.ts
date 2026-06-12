// Pure message-queue helpers for sequential chat sends (upstream pattern:
// messages sent while a run is active are queued and auto-dispatched when the
// current run completes/fails). Kept as pure functions so the queue logic is
// unit-testable without mocking the whole chat store.
import type { Attachment } from './chat'

export interface QueuedMessage {
  id: string
  content: string
  attachments?: Attachment[]
}

export function enqueueMessage(queue: QueuedMessage[], item: QueuedMessage): QueuedMessage[] {
  return [...queue, item]
}

export function dequeueMessage(queue: QueuedMessage[]): { next: QueuedMessage | null, rest: QueuedMessage[] } {
  if (queue.length === 0) return { next: null, rest: queue }
  return { next: queue[0], rest: queue.slice(1) }
}

export function removeQueuedMessage(queue: QueuedMessage[], id: string): QueuedMessage[] {
  return queue.filter(m => m.id !== id)
}

// Compact chip preview: first `max` chars of the text, falling back to the
// attachment names for attachment-only messages.
export function queuePreview(item: QueuedMessage, max = 40): string {
  const text = item.content.trim()
  if (text) return text.length > max ? text.slice(0, max) + '…' : text
  if (item.attachments?.length) {
    const names = item.attachments.map(a => a.name).join(', ')
    return names.length > max ? names.slice(0, max) + '…' : names
  }
  return ''
}
