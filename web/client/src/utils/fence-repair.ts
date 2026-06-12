/**
 * Repair unclosed markdown code fences in a streaming-partial markdown string.
 *
 * While an assistant reply streams in, a code block's opening ``` may have
 * arrived without its closing fence yet, which makes the rest of the message
 * render as one giant code block. This appends a temporary closing fence so
 * the intermediate render stays sane. Inline code (single backticks) is never
 * touched — only full fence lines (``` at line start, up to 3 leading spaces,
 * optionally followed by a language tag) are counted.
 */
const FENCE_LINE = /^ {0,3}```/

export function repairUnclosedFences(markdown: string): string {
  if (!markdown.includes('```')) return markdown

  let fenceCount = 0
  for (const line of markdown.split('\n')) {
    if (FENCE_LINE.test(line)) fenceCount++
  }

  if (fenceCount % 2 === 0) return markdown
  return markdown.endsWith('\n') ? markdown + '```' : markdown + '\n```'
}
