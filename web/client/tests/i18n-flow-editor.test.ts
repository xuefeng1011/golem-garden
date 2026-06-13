import { describe, it, expect } from 'vitest'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import ko from '@/i18n/locales/ko'

/**
 * Guards against vue-i18n message-compilation crashes.
 *
 * vue-i18n uses `{x}` for interpolation, so a raw `{{x}}` in a message is parsed
 * as an illegal *nested* placeholder and throws at render time — which previously
 * crashed StepFormPanel's agent form (insertRefHint) and froze the whole editor.
 * Calling t() on every flowEditor key forces lazy compilation; any offender throws.
 */
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: { en, ko },
})

const locales = [
  { name: 'en', dict: en.flowEditor as Record<string, unknown> },
  { name: 'ko', dict: ko.flowEditor as Record<string, unknown> },
]

describe('flowEditor i18n messages compile without nested-placeholder errors', () => {
  for (const { name, dict } of locales) {
    it(`${name}: every flowEditor message compiles`, () => {
      const t = i18n.global.t
      i18n.global.locale.value = name as 'en' | 'ko'
      for (const key of Object.keys(dict)) {
        // Must not throw a "Message compilation error: Not allowed nest placeholder".
        expect(() => t(`flowEditor.${key}`)).not.toThrow()
      }
    })
  }

  it('insertRefHint renders the literal {{id}} braces (not parsed as placeholder)', () => {
    const t = i18n.global.t
    i18n.global.locale.value = 'en'
    expect(t('flowEditor.insertRefHint')).toContain('{{step-id}}')
    i18n.global.locale.value = 'ko'
    expect(t('flowEditor.insertRefHint')).toContain('{{단계id}}')
  })
})
