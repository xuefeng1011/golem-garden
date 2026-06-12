import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import MailboxFeed from '@/components/hermes/activity/MailboxFeed.vue'
import type { MailboxMessage } from '@/api/hermes/souls'

function makeMsg(partial: Partial<MailboxMessage> = {}): MailboxMessage {
  return {
    from: 'nova',
    to: 'sage',
    type: 'task_assign',
    content: 'Please review the PR',
    ts: new Date().toISOString(),
    ...partial,
  }
}

function mountFeed(messages: MailboxMessage[]) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(MailboxFeed, {
    props: { messages },
    global: { plugins: [i18n] },
  })
}

describe('MailboxFeed', () => {
  it('renders from, arrow, and to for a message', () => {
    const wrapper = mountFeed([makeMsg({ from: 'nova', to: 'sage' })])
    expect(wrapper.find('.feed-from').text()).toBe('nova')
    expect(wrapper.find('.feed-arrow').text()).toBe('→')
    expect(wrapper.find('.feed-to').text()).toBe('sage')
  })

  it('renders the message content', () => {
    const wrapper = mountFeed([makeMsg({ content: 'Deploy to staging' })])
    expect(wrapper.find('.feed-content').text()).toBe('Deploy to staging')
  })

  it('renders the type tag', () => {
    const wrapper = mountFeed([makeMsg({ type: 'task_done' })])
    expect(wrapper.find('.feed-type-tag').text()).toBe('task_done')
  })

  it('shows EmptyState when messages array is empty', () => {
    const wrapper = mountFeed([])
    expect(wrapper.find('.empty-title').exists()).toBe(true)
    expect(wrapper.find('.feed-list').exists()).toBe(false)
  })

  it('renders multiple messages', () => {
    const wrapper = mountFeed([
      makeMsg({ from: 'a', to: 'b' }),
      makeMsg({ from: 'c', to: 'd' }),
    ])
    expect(wrapper.findAll('.feed-item')).toHaveLength(2)
  })

  it('truncates content longer than 100 chars', () => {
    const long = 'x'.repeat(150)
    const wrapper = mountFeed([makeMsg({ content: long })])
    const text = wrapper.find('.feed-content').text()
    expect(text.length).toBeLessThanOrEqual(104) // 100 chars + '…'
    expect(text.endsWith('…')).toBe(true)
  })
})
