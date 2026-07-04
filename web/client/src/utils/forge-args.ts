// forge args 계약: 각 인자 ≤512자, 개행 금지, `;|&<>` 백틱 `$` 금지 (gateway forge_runner
// _FORBIDDEN_ARG_CHARS 화이트리스트와 정합).
// 클라이언트에서 선제 검증해 서버 왕복 없이 친절한 오류를 보여준다.
const MAX_FORGE_ARG_LENGTH = 512
const FORBIDDEN_CHARS_RE = /[;|&<>`$]/

export type ForgeArgError = 'tooLong' | 'newline' | 'forbiddenChars'

export function validateForgeArg(value: string): ForgeArgError | null {
  if (value.includes('\n') || value.includes('\r')) return 'newline'
  if (value.length > MAX_FORGE_ARG_LENGTH) return 'tooLong'
  if (FORBIDDEN_CHARS_RE.test(value)) return 'forbiddenChars'
  return null
}
