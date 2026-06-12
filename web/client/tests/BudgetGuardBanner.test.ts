import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import BudgetGuardBanner from '@/components/hermes/chat/BudgetGuardBanner.vue'
import type { ProjectBudget } from '@/api/hermes/budget'

function makeBudget(overrides: Partial<ProjectBudget> = {}): ProjectBudget {
  return {
    total_cost_usd: 1.0,
    by_soul: [],
    daily: [],
    budget_limit_usd: 2.0,
    warning: null,
    ...overrides,
  }
}

function mountBanner(budget: ProjectBudget | null) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(BudgetGuardBanner, {
    props: { budget },
    global: { plugins: [i18n] },
  })
}

describe('BudgetGuardBanner', () => {
  it('is hidden when usage is below 80%', () => {
    // 1.0 / 2.0 = 50%
    const wrapper = mountBanner(makeBudget({ total_cost_usd: 1.0, budget_limit_usd: 2.0 }))
    expect(wrapper.find('.budget-guard-banner').exists()).toBe(false)
  })

  it('shows warning tone at 80-99% usage', () => {
    // 1.7 / 2.0 = 85%
    const wrapper = mountBanner(makeBudget({ total_cost_usd: 1.7, budget_limit_usd: 2.0 }))
    const banner = wrapper.find('.budget-guard-banner')
    expect(banner.exists()).toBe(true)
    expect(banner.classes()).toContain('banner--warning')
    expect(banner.classes()).not.toContain('banner--blocked')
    expect(wrapper.text()).toContain('85.0%')
  })

  it('shows blocked tone at >=100% usage', () => {
    // 2.1 / 2.0 = 105%
    const wrapper = mountBanner(makeBudget({ total_cost_usd: 2.1, budget_limit_usd: 2.0 }))
    const banner = wrapper.find('.budget-guard-banner')
    expect(banner.exists()).toBe(true)
    expect(banner.classes()).toContain('banner--blocked')
    expect(banner.classes()).not.toContain('banner--warning')
    expect(wrapper.text()).toContain('GOLEM_BUDGET_OVERRIDE=1')
  })

  it('hides banner when budget_limit_usd is null', () => {
    const wrapper = mountBanner(makeBudget({ budget_limit_usd: null, total_cost_usd: 999 }))
    expect(wrapper.find('.budget-guard-banner').exists()).toBe(false)
  })

  it('dismisses banner on close button click', async () => {
    const wrapper = mountBanner(makeBudget({ total_cost_usd: 1.7, budget_limit_usd: 2.0 }))
    expect(wrapper.find('.budget-guard-banner').exists()).toBe(true)
    await wrapper.find('.banner-dismiss').trigger('click')
    expect(wrapper.find('.budget-guard-banner').exists()).toBe(false)
  })

  it('shows warning tone when warning string is set even below 80%', () => {
    const wrapper = mountBanner(
      makeBudget({
        total_cost_usd: 1.0,
        budget_limit_usd: 2.0,
        warning: 'Approaching budget limit',
      }),
    )
    const banner = wrapper.find('.budget-guard-banner')
    expect(banner.exists()).toBe(true)
    expect(banner.classes()).toContain('banner--warning')
  })
})
