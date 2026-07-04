import { describe, it, expect } from 'vitest'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import ko from '@/i18n/locales/ko'

/**
 * Guards against vue-i18n message-compilation crashes for the flowStudio.*
 * namespace — mirrors tests/i18n-flow-editor.test.ts. A raw `{{x}}` in a
 * message is parsed as an illegal nested placeholder and throws at render
 * time, which previously crashed the flow editor's agent form.
 */
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: 'en',
  messages: { en, ko },
})

function flattenKeys(obj: Record<string, unknown>, prefix = ''): string[] {
  const keys: string[] = []
  for (const [key, value] of Object.entries(obj)) {
    const full = prefix ? `${prefix}.${key}` : key
    if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
      keys.push(...flattenKeys(value as Record<string, unknown>, full))
    } else {
      keys.push(full)
    }
  }
  return keys
}

const locales = [
  { name: 'en', dict: en.flowStudio as Record<string, unknown> },
  { name: 'ko', dict: ko.flowStudio as Record<string, unknown> },
]

describe('flowStudio i18n messages compile without nested-placeholder errors', () => {
  for (const { name, dict } of locales) {
    it(`${name}: every flowStudio message compiles`, () => {
      const t = i18n.global.t
      i18n.global.locale.value = name as 'en' | 'ko'
      for (const key of flattenKeys(dict)) {
        expect(() => t(`flowStudio.${key}`)).not.toThrow()
      }
    })
  }

  it('sidebar.flowEditor is relabeled to project-scoped wording', () => {
    const t = i18n.global.t
    i18n.global.locale.value = 'en'
    expect(t('sidebar.flowEditor')).toBe('Project Flows')
    i18n.global.locale.value = 'ko'
    expect(t('sidebar.flowEditor')).toBe('프로젝트 플로우')
  })

  it('sidebar.flowStudio exists for both locales', () => {
    const t = i18n.global.t
    i18n.global.locale.value = 'en'
    expect(t('sidebar.flowStudio')).not.toBe('sidebar.flowStudio')
    i18n.global.locale.value = 'ko'
    expect(t('sidebar.flowStudio')).not.toBe('sidebar.flowStudio')
  })
})
