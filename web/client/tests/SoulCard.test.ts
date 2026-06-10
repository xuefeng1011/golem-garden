import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import SoulCard from '@/components/hermes/souls/SoulCard.vue'
import type { Soul } from '@/api/hermes/souls'

function makeSoul(partial: Partial<Soul> = {}): Soul {
  return {
    id: 'nova',
    name: 'Nova',
    rank: 'junior',
    specialty: ['frontend', 'vue'],
    description: 'Frontend specialist',
    ...partial,
  }
}

describe('SoulCard', () => {
  it('renders name, rank badge, and description', () => {
    const wrapper = mount(SoulCard, { props: { soul: makeSoul() } })
    expect(wrapper.find('.soul-name').text()).toBe('Nova')
    const rank = wrapper.find('.rank-tag')
    expect(rank.text()).toBe('junior')
    expect(rank.classes()).toContain('rank-junior')
    expect(wrapper.find('.soul-description').text()).toBe('Frontend specialist')
  })

  it('shows all specialty tags when 3 or fewer', () => {
    const wrapper = mount(SoulCard, {
      props: { soul: makeSoul({ specialty: ['a', 'b', 'c'] }) },
    })
    const tags = wrapper.findAll('.specialty-tag')
    expect(tags).toHaveLength(3)
    expect(wrapper.find('.overflow-tag').exists()).toBe(false)
  })

  it('truncates specialty tags to 3 and shows +N overflow tag', () => {
    const wrapper = mount(SoulCard, {
      props: { soul: makeSoul({ specialty: ['a', 'b', 'c', 'd', 'e'] }) },
    })
    const tags = wrapper.findAll('.specialty-tag')
    // 3 visible + 1 overflow indicator
    expect(tags).toHaveLength(4)
    const overflow = wrapper.find('.overflow-tag')
    expect(overflow.exists()).toBe(true)
    expect(overflow.text()).toBe('+2')
    expect(overflow.attributes('title')).toBe('d, e')
  })

  it('renders no specialty section when list is empty', () => {
    const wrapper = mount(SoulCard, { props: { soul: makeSoul({ specialty: [] }) } })
    expect(wrapper.find('.specialty-chips').exists()).toBe(false)
  })

  it('emits click when the card is clicked', async () => {
    const wrapper = mount(SoulCard, { props: { soul: makeSoul() } })
    await wrapper.find('.soul-card').trigger('click')
    expect(wrapper.emitted('click')).toHaveLength(1)
  })
})
