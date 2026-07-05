import { describe, expect, it } from 'vitest'
import { adaptArtifact, type RawArtifact } from '@/api/hermes/artifacts'

function raw(overrides: Partial<RawArtifact> = {}): RawArtifact {
  return {
    path: 'reports/summary.md',
    name: 'summary.md',
    size: 1234,
    mtime: '2026-07-05T00:00:00',
    ...overrides,
  }
}

describe('artifacts adapter — gateway payload → UI model (단일 매핑 지점)', () => {
  it('maps path/name/size/mtime through unchanged', () => {
    const artifact = adaptArtifact(raw())
    expect(artifact.path).toBe('reports/summary.md')
    expect(artifact.name).toBe('summary.md')
    expect(artifact.size).toBe(1234)
    expect(artifact.mtime).toBe('2026-07-05T00:00:00')
  })

  it('handles root-level artifacts (no directory prefix)', () => {
    const artifact = adaptArtifact(raw({ path: 'result.txt', name: 'result.txt' }))
    expect(artifact.path).toBe('result.txt')
  })

  it('handles zero-byte files', () => {
    const artifact = adaptArtifact(raw({ size: 0 }))
    expect(artifact.size).toBe(0)
  })
})
