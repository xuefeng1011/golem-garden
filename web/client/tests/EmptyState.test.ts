import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { h, markRaw } from 'vue'
import EmptyState from '@/components/common/EmptyState.vue'

describe('EmptyState', () => {
  it('renders title', () => {
    const wrapper = mount(EmptyState, { props: { title: 'No souls yet' } })
    expect(wrapper.find('.empty-title').text()).toBe('No souls yet')
  })

  it('renders description when provided', () => {
    const wrapper = mount(EmptyState, {
      props: { title: 'Empty', description: 'Create your first SOUL' },
    })
    expect(wrapper.find('.empty-description').text()).toBe('Create your first SOUL')
  })

  it('hides description when not provided', () => {
    const wrapper = mount(EmptyState, { props: { title: 'Empty' } })
    expect(wrapper.find('.empty-description').exists()).toBe(false)
  })

  it('renders action button and calls handler on click', async () => {
    const handler = vi.fn()
    const wrapper = mount(EmptyState, {
      props: { title: 'Empty', action: { label: 'Create', handler } },
    })
    const button = wrapper.find('.empty-action')
    expect(button.text()).toBe('Create')
    await button.trigger('click')
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it('hides action button when no action provided', () => {
    const wrapper = mount(EmptyState, { props: { title: 'Empty' } })
    expect(wrapper.find('.empty-action').exists()).toBe(false)
  })

  it('prefers icon slot over icon prop', () => {
    const IconProp = markRaw({ render: () => h('svg', { class: 'prop-icon' }) })
    const wrapper = mount(EmptyState, {
      props: { title: 'Empty', icon: IconProp },
      slots: { icon: '<svg class="slot-icon" />' },
    })
    expect(wrapper.find('.slot-icon').exists()).toBe(true)
    expect(wrapper.find('.prop-icon').exists()).toBe(false)
  })

  it('renders icon prop component when no slot given', () => {
    const IconProp = markRaw({ render: () => h('svg', { class: 'prop-icon' }) })
    const wrapper = mount(EmptyState, {
      props: { title: 'Empty', icon: IconProp },
    })
    expect(wrapper.find('.prop-icon').exists()).toBe(true)
  })

  it('hides icon container when neither slot nor prop given', () => {
    const wrapper = mount(EmptyState, { props: { title: 'Empty' } })
    expect(wrapper.find('.empty-icon').exists()).toBe(false)
  })
})
