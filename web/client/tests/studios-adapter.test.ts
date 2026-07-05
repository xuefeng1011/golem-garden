import { describe, expect, it, vi } from 'vitest'
import { adaptStudio, deleteStudio, type RawStudio } from '@/api/hermes/studios'
import { request } from '@/api/client'

vi.mock('@/api/client', () => ({
  request: vi.fn(),
}))

function raw(overrides: Partial<RawStudio> = {}): RawStudio {
  return {
    id: 'studio_1',
    name: 'Market Research',
    path: 'C:/01_xuefeng/market-research',
    created_at: '2026-07-04T00:00:00',
    kind: 'studio',
    goal: 'Research the market',
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

  it('maps goal through unchanged', () => {
    expect(adaptStudio(raw({ goal: 'Grow the garden' })).goal).toBe('Grow the garden')
  })

  it('defaults goal to empty string when absent (backward compat)', () => {
    expect(adaptStudio(raw({ goal: undefined })).goal).toBe('')
  })
})

describe('deleteStudio — registry-only removal (disk untouched)', () => {
  it('sends a DELETE request to /v1/studios/{id}', async () => {
    vi.mocked(request).mockResolvedValue(undefined)
    await deleteStudio('studio_1')
    expect(request).toHaveBeenCalledWith('/v1/studios/studio_1', { method: 'DELETE' })
  })

  it('URL-encodes the studio id', async () => {
    vi.mocked(request).mockResolvedValue(undefined)
    await deleteStudio('studio with space')
    expect(request).toHaveBeenCalledWith('/v1/studios/studio%20with%20space', { method: 'DELETE' })
  })

  it('propagates errors from the request layer (e.g. 404 unknown/non-studio id)', async () => {
    vi.mocked(request).mockRejectedValue(new Error('API Error 404: not found'))
    await expect(deleteStudio('missing')).rejects.toThrow('404')
  })
})
