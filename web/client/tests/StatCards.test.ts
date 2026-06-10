import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import StatCards from '@/components/hermes/overview/StatCards.vue'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import en from '@/i18n/locales/en'
import type { ProjectOverview } from '@/api/hermes/overview'

function makeOverview(partial: Partial<ProjectOverview> = {}): ProjectOverview {
  return {
    project_id: 'p1',
    name: 'Demo',
    souls_count: 4,
    active_souls: [],
    recent_activity: [],
    total_tasks: 42,
    success_rate: 85.5,
    total_cost_usd: 1.23,
    last_activity_ts: '',
    ...partial,
  }
}

function mountStatCards(props: { overview?: ProjectOverview | null; loading?: boolean }) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(StatCards, { props, global: { plugins: [i18n] } })
}

describe('StatCards', () => {
  it('renders 4 skeleton cards while loading', () => {
    const wrapper = mountStatCards({ loading: true })
    expect(wrapper.find('[data-testid="stat-skeleton"]').exists()).toBe(true)
    expect(wrapper.findAllComponents(SkeletonCard)).toHaveLength(4)
    expect(wrapper.find('.stat-value').exists()).toBe(false)
  })

  it('renders stat values when overview is provided', () => {
    const wrapper = mountStatCards({ overview: makeOverview() })
    const values = wrapper.findAll('.stat-value')
    expect(values).toHaveLength(4)
    expect(values[0].text()).toBe('42')
    expect(values[1].text()).toBe('85.5%')
    expect(values[2].text()).toBe('$1.23')
    expect(values[3].text()).toBe('4')
  })

  it('renders nothing when neither loading nor overview', () => {
    const wrapper = mountStatCards({ overview: null })
    expect(wrapper.find('.stat-cards').exists()).toBe(false)
  })

  it('marks high success rate with success semantic class', () => {
    const wrapper = mountStatCards({ overview: makeOverview({ success_rate: 92 }) })
    expect(wrapper.find('[data-testid="success-rate"]').classes()).toContain('is-success')
  })

  it('marks low success rate with warning semantic class', () => {
    const wrapper = mountStatCards({ overview: makeOverview({ success_rate: 25 }) })
    expect(wrapper.find('[data-testid="success-rate"]').classes()).toContain('is-warning')
  })

  it('stays neutral when there are no tasks', () => {
    const wrapper = mountStatCards({
      overview: makeOverview({ total_tasks: 0, success_rate: 0 }),
    })
    const el = wrapper.find('[data-testid="success-rate"]')
    expect(el.classes()).not.toContain('is-success')
    expect(el.classes()).not.toContain('is-warning')
  })
})
