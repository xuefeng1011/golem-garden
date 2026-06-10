import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import RankProgress from '@/components/common/RankProgress.vue'

function mountRankProgress(props: {
  current: string
  next?: string | null
  tasksToPromote?: number
}) {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: {
      en: {
        common: {
          maxRank: 'Max rank reached',
          tasksToPromote: '{n} tasks to next rank',
        },
      },
    },
  })
  return mount(RankProgress, { props, global: { plugins: [i18n] } })
}

describe('RankProgress', () => {
  it('renders current rank badge with rank color class', () => {
    const wrapper = mountRankProgress({ current: 'junior', next: 'senior' })
    const badge = wrapper.find('.rank-badge')
    expect(badge.text()).toBe('junior')
    expect(badge.classes()).toContain('rank-junior')
  })

  it('renders next rank badge when promotion is possible', () => {
    const wrapper = mountRankProgress({ current: 'novice', next: 'junior' })
    const badges = wrapper.findAll('.rank-badge')
    expect(badges).toHaveLength(2)
    expect(badges[1].text()).toBe('junior')
    expect(badges[1].classes()).toContain('rank-next')
  })

  it('shows tasks-to-promote caption', () => {
    const wrapper = mountRankProgress({
      current: 'novice',
      next: 'junior',
      tasksToPromote: 5,
    })
    expect(wrapper.find('.progress-caption').text()).toBe('5 tasks to next rank')
  })

  it('hides caption when tasksToPromote is missing and not max rank', () => {
    const wrapper = mountRankProgress({ current: 'novice', next: 'junior' })
    expect(wrapper.find('.progress-caption').exists()).toBe(false)
  })

  it('shows max-rank state when next is null', () => {
    const wrapper = mountRankProgress({ current: 'master', next: null })
    expect(wrapper.find('.progress-caption').text()).toBe('Max rank reached')
    expect(wrapper.findAll('.rank-badge')).toHaveLength(1)
    const fill = wrapper.find('.progress-fill')
    expect(fill.classes()).toContain('progress-max')
    expect(fill.attributes('style')).toContain('width: 100%')
  })

  it('computes progress from rank ladder position', () => {
    const wrapper = mountRankProgress({ current: 'junior', next: 'senior' })
    expect(wrapper.find('.progress-track').attributes('aria-valuenow')).toBe('50')
    expect(wrapper.find('.progress-fill').attributes('style')).toContain('width: 50%')
  })

  it('treats missing next as max rank even below master', () => {
    const wrapper = mountRankProgress({ current: 'senior' })
    expect(wrapper.find('.progress-caption').text()).toBe('Max rank reached')
  })
})
