import { describe, it, expect, vi, afterEach } from 'vitest'
import { request, ApiError } from '@/api/client'

function mockFetchOnce(res: Partial<Response> & { json?: () => Promise<unknown> }) {
  const fullRes = {
    ok: true,
    status: 200,
    statusText: 'OK',
    headers: new Headers(),
    json: vi.fn().mockRejectedValue(new SyntaxError('Unexpected end of JSON input')),
    text: vi.fn().mockResolvedValue(''),
    ...res,
  } as unknown as Response
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(fullRes))
  return fullRes
}

describe('request() — 204 / empty-body handling', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('204 No Content resolves to undefined instead of calling res.json()', async () => {
    const res = mockFetchOnce({ status: 204 })
    await expect(request('/v1/studios/studio_1', { method: 'DELETE' })).resolves.toBeUndefined()
    expect(res.json).not.toHaveBeenCalled()
  })

  it('200 with content-length: 0 also resolves to undefined without parsing JSON', async () => {
    const res = mockFetchOnce({
      status: 200,
      headers: new Headers({ 'content-length': '0' }),
    })
    await expect(request('/v1/some-endpoint', { method: 'DELETE' })).resolves.toBeUndefined()
    expect(res.json).not.toHaveBeenCalled()
  })

  it('200 with a JSON body still parses and returns it', async () => {
    mockFetchOnce({
      status: 200,
      json: vi.fn().mockResolvedValue({ id: 'studio_1' }),
    })
    await expect(request('/v1/studios/studio_1')).resolves.toEqual({ id: 'studio_1' })
  })

  it('non-2xx still throws ApiError and never reaches the 204 short-circuit', async () => {
    mockFetchOnce({ ok: false, status: 404, statusText: 'Not Found' })
    await expect(request('/v1/studios/missing')).rejects.toBeInstanceOf(ApiError)
  })
})
