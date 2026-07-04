import { describe, expect, it } from 'vitest'
import { adaptStudio, type RawStudio } from '@/api/hermes/studios'

function raw(overrides: Partial<RawStudio> = {}): RawStudio {
  return {
    id: 'studio_1',
    name: 'Market Research',
    path: 'C:/01_xuefeng/market-research',
    created_at: '2026-07-04T00:00:00',
    kind: 'studio',
    ...overrides,
  }
}

describe('studios adapter — gateway snake_case → UI camelCase (단일 매핑 지점)', () => {
  it('maps id/name/path through unchanged', () => {
    const studio = adaptStudio(raw())
    expect(studio.id).toBe('studio_1')
    expect(studio.name).toBe('Market Research')
    expect(studio.path).toBe('C:/01_xuefeng/market-research')
  })

  it('maps created_at → createdAt', () => {
    const studio = adaptStudio(raw({ created_at: '2026-01-02T03:04:05' }))
    expect(studio.createdAt).toBe('2026-01-02T03:04:05')
  })

  it('kind is always studio regardless of raw payload', () => {
    expect(adaptStudio(raw({ kind: undefined })).kind).toBe('studio')
    expect(adaptStudio(raw({ kind: 'project' })).kind).toBe('studio')
  })
})
