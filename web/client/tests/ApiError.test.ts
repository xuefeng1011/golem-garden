import { describe, it, expect } from 'vitest'
import { ApiError, classifyHttpStatus, kindToI18nKey } from '@/utils/api-error'

describe('classifyHttpStatus', () => {
  it('classifies 401 as auth', () => {
    expect(classifyHttpStatus(401)).toBe('auth')
  })

  it('classifies 403 as auth', () => {
    expect(classifyHttpStatus(403)).toBe('auth')
  })

  it('classifies 404 as notfound', () => {
    expect(classifyHttpStatus(404)).toBe('notfound')
  })

  it('classifies 500 as server', () => {
    expect(classifyHttpStatus(500)).toBe('server')
  })

  it('classifies 503 as server', () => {
    expect(classifyHttpStatus(503)).toBe('server')
  })

  it('classifies 400 as client', () => {
    expect(classifyHttpStatus(400)).toBe('client')
  })

  it('classifies 422 as client', () => {
    expect(classifyHttpStatus(422)).toBe('client')
  })
})

describe('ApiError', () => {
  it('fetch TypeError (network failure) → kind=network, status=null', () => {
    const err = new ApiError('API Error network: Failed to fetch', null, 'network')
    expect(err.kind).toBe('network')
    expect(err.status).toBeNull()
    expect(err).toBeInstanceOf(Error)
    expect(err).toBeInstanceOf(ApiError)
  })

  it('HTTP 404 → kind=notfound', () => {
    const err = new ApiError('API Error 404: Not Found', 404, 'notfound')
    expect(err.kind).toBe('notfound')
    expect(err.status).toBe(404)
    // message preserves legacy format for backward compatibility
    expect(err.message).toBe('API Error 404: Not Found')
  })

  it('HTTP 500 → kind=server', () => {
    const err = new ApiError('API Error 500: Internal Server Error', 500, 'server')
    expect(err.kind).toBe('server')
    expect(err.status).toBe(500)
  })

  it('HTTP 403 → kind=auth', () => {
    const err = new ApiError('API Error 403: Forbidden', 403, 'auth')
    expect(err.kind).toBe('auth')
    expect(err.status).toBe(403)
  })

  it('HTTP 400 → kind=client', () => {
    const err = new ApiError('API Error 400: Bad Request', 400, 'client')
    expect(err.kind).toBe('client')
    expect(err.status).toBe(400)
  })
})

describe('kindToI18nKey', () => {
  it('maps network → common.errorNetwork', () => {
    const err = new ApiError('', null, 'network')
    expect(kindToI18nKey(err)).toBe('common.errorNetwork')
  })

  it('maps auth → common.errorAuth', () => {
    const err = new ApiError('', 403, 'auth')
    expect(kindToI18nKey(err)).toBe('common.errorAuth')
  })

  it('maps notfound → common.errorNotFound', () => {
    const err = new ApiError('', 404, 'notfound')
    expect(kindToI18nKey(err)).toBe('common.errorNotFound')
  })

  it('maps server → common.errorServer', () => {
    const err = new ApiError('', 500, 'server')
    expect(kindToI18nKey(err)).toBe('common.errorServer')
  })

  it('maps client → common.errorGeneric', () => {
    const err = new ApiError('', 400, 'client')
    expect(kindToI18nKey(err)).toBe('common.errorGeneric')
  })
})
