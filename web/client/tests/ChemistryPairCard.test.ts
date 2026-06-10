import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import ChemistryPairCard from '@/components/hermes/team/ChemistryPairCard.vue'
import type { ChemistryPair } from '@/api/hermes/chemistry'

function mountCard(pair: ChemistryPair, maxScore = 0) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(ChemistryPairCard, {
    props: { pair, maxScore },
    global: { plugins: [i18n] },
  })
}

describe('ChemistryPairCard', () => {
  it('renders both soul names, score and interaction count', () => {
    const wrapper = mountCard(
      { souls: ['iron', 'pixel'], score: 42, interactions: 7 },
      42,
    )
    const names = wrapper.findAll('.soul-name').map((el) => el.text())
    expect(names).toEqual(['iron', 'pixel'])
    expect(wrapper.find('.score-badge').text()).toBe('Score 42')
    expect(wrapper.find('.interactions').text()).toBe('7 collabs')
  })

  it('applies accent styling to high-score pairs only', () => {
    const top = mountCard(
      { souls: ['iron', 'pixel'], score: 90, interactions: 5 },
      100,
    )
    expect(top.classes()).toContain('pair-accent')

    const weak = mountCard(
      { souls: ['sage', 'echo'], score: 20, interactions: 1 },
      100,
    )
    expect(weak.classes()).not.toContain('pair-accent')
  })

  it('renders a placeholder for null score without accent', () => {
    const wrapper = mountCard(
      { souls: ['iron', 'echo'], score: null, interactions: 3 },
      100,
    )
    expect(wrapper.find('.score-badge').text()).toBe('Score —')
    expect(wrapper.classes()).not.toContain('pair-accent')
  })
})
