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
