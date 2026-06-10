import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import SkeletonCard from '@/components/common/SkeletonCard.vue'

describe('SkeletonCard', () => {
  it('renders 3 rows by default', () => {
    const wrapper = mount(SkeletonCard)
    expect(wrapper.findAll('.skeleton-line')).toHaveLength(3)
  })

  it('renders custom row count', () => {
    const wrapper = mount(SkeletonCard, { props: { rows: 5 } })
    expect(wrapper.findAll('.skeleton-line')).toHaveLength(5)
  })

  it('hides avatar by default', () => {
    const wrapper = mount(SkeletonCard)
    expect(wrapper.find('.skeleton-avatar').exists()).toBe(false)
  })

  it('shows avatar header when showAvatar is true', () => {
    const wrapper = mount(SkeletonCard, { props: { showAvatar: true } })
    expect(wrapper.find('.skeleton-avatar').exists()).toBe(true)
    expect(wrapper.find('.skeleton-title').exists()).toBe(true)
    // 3 body rows + 1 title line
    expect(wrapper.findAll('.skeleton-line')).toHaveLength(4)
  })

  it('marks itself busy for accessibility', () => {
    const wrapper = mount(SkeletonCard)
    expect(wrapper.attributes('aria-busy')).toBe('true')
  })

  it('applies shimmer animation class to every line', () => {
    const wrapper = mount(SkeletonCard, { props: { rows: 2 } })
    for (const line of wrapper.findAll('.skeleton-line')) {
      expect(line.classes()).toContain('shimmer')
    }
  })
})
