import type { SoulDetail } from '@/api/hermes/souls'

// Maps effort level to NTag type
export function effortTagType(
  effort: SoulDetail['effort'],
): 'success' | 'info' | 'warning' | 'default' {
  if (effort === 'low') return 'success'
  if (effort === 'medium') return 'info'
  if (effort === 'high') return 'warning'
  return 'default'
}

// Maps isolation mode to NTag type
export function isolationTagType(
  isolation: SoulDetail['isolation'],
): 'info' | 'default' {
  return isolation === 'worktree' ? 'info' : 'default'
}

// Returns true when disallowed_tools section should be visible
export function showDisallowedTools(disallowed: string[]): boolean {
  return Array.isArray(disallowed) && disallowed.length > 0
}

// Formats max_turns for display; null/undefined → fallback string
export function formatMaxTurns(
  maxTurns: number | null | undefined,
  defaultLabel: string,
): string {
  if (maxTurns !== null && maxTurns !== undefined) return `${maxTurns}턴`
  return defaultLabel
}
