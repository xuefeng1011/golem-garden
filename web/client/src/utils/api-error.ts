export type ApiErrorKind = 'network' | 'auth' | 'notfound' | 'server' | 'client'

export class ApiError extends Error {
  readonly status: number | null
  readonly kind: ApiErrorKind

  constructor(message: string, status: number | null, kind: ApiErrorKind) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.kind = kind
  }
}

export function classifyHttpStatus(status: number): ApiErrorKind {
  if (status === 401 || status === 403) return 'auth'
  if (status === 404) return 'notfound'
  if (status >= 500) return 'server'
  return 'client'
}

/**
 * Returns an i18n key for the given ApiError kind.
 * Falls back to 'common.errorGeneric' for unknown kinds.
 */
export function kindToI18nKey(err: ApiError): string {
  switch (err.kind) {
    case 'network':
      return 'common.errorNetwork'
    case 'auth':
      return 'common.errorAuth'
    case 'notfound':
      return 'common.errorNotFound'
    case 'server':
      return 'common.errorServer'
    default:
      return 'common.errorGeneric'
  }
}
