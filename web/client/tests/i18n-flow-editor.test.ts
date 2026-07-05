import { describe, it, expect } from 'vitest'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import ko from '@/i18n/locales/ko'
import de from '@/i18n/locales/de'
import es from '@/i18n/locales/es'
import fr from '@/i18n/locales/fr'
import ja from '@/i18n/locales/ja'
import pt from '@/i18n/locales/pt'

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
  messages: { en, ko, de, es, fr, ja, pt },
})

const locales = [
  { name: 'en', dict: en.flowEditor as Record<string, unknown> },
  { name: 'ko', dict: ko.flowEditor as Record<string, unknown> },
  { name: 'de', dict: de.flowEditor as Record<string, unknown> },
  { name: 'es', dict: es.flowEditor as Record<string, unknown> },
  { name: 'fr', dict: fr.flowEditor as Record<string, unknown> },
  { name: 'ja', dict: ja.flowEditor as Record<string, unknown> },
  { name: 'pt', dict: pt.flowEditor as Record<string, unknown> },
]

describe('flowEditor i18n messages compile without nested-placeholder errors', () => {
  for (const { name, dict } of locales) {
    it(`${name}: every flowEditor message compiles`, () => {
      const t = i18n.global.t
      i18n.global.locale.value = name as 'en' | 'ko' | 'de' | 'es' | 'fr' | 'ja' | 'pt'
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
    for (const name of ['de', 'es', 'fr', 'ja', 'pt'] as const) {
      i18n.global.locale.value = name
      expect(t('flowEditor.insertRefHint')).toContain('{{step-id}}')
    }
  })
})
