import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import BudgetSummaryCards from '@/components/hermes/usage/BudgetSummaryCards.vue'
import type { ProjectBudget } from '@/api/hermes/budget'

function mountCards(budget: ProjectBudget) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(BudgetSummaryCards, {
    props: { budget },
    global: { plugins: [i18n] },
  })
}

const baseBudget: ProjectBudget = {
  total_cost_usd: 1.5,
  by_soul: [
    { soul: 'iron', cost_usd: 1.0, tasks: 4 },
    { soul: 'pixel', cost_usd: 0.5, tasks: 2 },
  ],
  daily: [],
  budget_limit_usd: 2.0,
  warning: null,
}

describe('BudgetSummaryCards', () => {
  it('renders total cost, usage percent, task and soul counts', () => {
    const wrapper = mountCards(baseBudget)
    expect(wrapper.text()).toContain('$1.50')
    expect(wrapper.text()).toContain('75.0%')
    expect(wrapper.text()).toContain('of $2.00 limit')
    const values = wrapper.findAll('.stat-value').map((el) => el.text())
    expect(values).toContain('6') // total tasks
    expect(values).toContain('2') // active souls
  })

  it('hides the warning badge when there is no warning', () => {
    const wrapper = mountCards(baseBudget)
    expect(wrapper.find('.warning-badge').exists()).toBe(false)
    expect(wrapper.find('.stat-warn').exists()).toBe(false)
  })

  it('shows the warning badge and warn styling when warning is set', () => {
    const wrapper = mountCards({
      ...baseBudget,
      total_cost_usd: 1.9,
      warning: 'Approaching budget limit: $1.900 / $2.00 (95%)',
    })
    const badge = wrapper.find('.warning-badge')
    expect(badge.exists()).toBe(true)
    expect(badge.text()).toBe('Warning')
    expect(badge.attributes('title')).toContain('Approaching budget limit')
    expect(wrapper.find('.stat-warn').exists()).toBe(true)
    expect(wrapper.text()).toContain('95.0%')
  })

  it('shows "no limit" instead of a percent when budget_limit_usd is null', () => {
    const wrapper = mountCards({ ...baseBudget, budget_limit_usd: null })
    expect(wrapper.text()).toContain('No limit set')
    expect(wrapper.text()).not.toContain('%')
  })
})
