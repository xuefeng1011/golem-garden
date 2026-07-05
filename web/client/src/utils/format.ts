/**
 * Format a USD amount consistently across the app.
 * - null / undefined / NaN → '—'
 * - amounts >= 1 → 2 decimal places (e.g. '$1.23')
 * - amounts < 1 → 3 decimal places (e.g. '$0.015')
 */
export function fmtUsd(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return '—'
  return '$' + n.toFixed(n >= 1 ? 2 : 3)
}

/**
 * Humanize a byte count (e.g. artifact file sizes).
 * - negative / non-finite → '—'
 * - < 1024 → whole bytes (e.g. '512 B')
 * - otherwise → largest unit with 1 decimal (0 decimals when >= 10)
 */
export function fmtBytes(n: number | null | undefined): string {
  if (n === null || n === undefined || !Number.isFinite(n) || n < 0) return '—'
  if (n < 1024) return `${n} B`
  const units = ['KB', 'MB', 'GB', 'TB']
  let value = n
  let unitIndex = -1
  do {
    value /= 1024
    unitIndex += 1
  } while (value >= 1024 && unitIndex < units.length - 1)
  return `${value.toFixed(value < 10 ? 1 : 0)} ${units[unitIndex]}`
}
