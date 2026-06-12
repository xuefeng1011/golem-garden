import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import ThinkingBlock from '@/components/hermes/chat/ThinkingBlock.vue'

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: { en: { chat: { thinkingLabel: 'Thinking process' } } },
})

function mountBlock(props: { text: string; streaming?: boolean }) {
  return mount(ThinkingBlock, {
    props,
    global: { plugins: [i18n] },
  })
}

describe('ThinkingBlock', () => {
  it('기본 접힘 — 본문 미표시', () => {
    const w = mountBlock({ text: 'deep thought' })
    expect(w.find('.thinking-body').exists()).toBe(false)
    expect(w.find('.thinking-label').text()).toBe('Thinking process')
  })

  it('헤더 클릭으로 펼침/접힘 토글', async () => {
    const w = mountBlock({ text: 'deep thought' })
    await w.find('.thinking-header').trigger('click')
    expect(w.find('.thinking-body').exists()).toBe(true)
    expect(w.find('.thinking-body').text()).toBe('deep thought')
    await w.find('.thinking-header').trigger('click')
    expect(w.find('.thinking-body').exists()).toBe(false)
  })

  it('streaming=true 면 점멸 dot', () => {
    const w = mountBlock({ text: 't', streaming: true })
    expect(w.find('.thinking-dot.pulse').exists()).toBe(true)
  })

  it('streaming 미지정이면 점멸 없음', () => {
    const w = mountBlock({ text: 't' })
    expect(w.find('.thinking-dot.pulse').exists()).toBe(false)
  })
})
