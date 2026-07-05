import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import StudioRedesignModal from '@/components/hermes/studio/StudioRedesignModal.vue'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'

vi.mock('@/api/hermes/forge', () => ({
  startForge: vi.fn(),
  streamForgeEvents: vi.fn(),
}))

function bodyButtons(): HTMLButtonElement[] {
  return Array.from(document.body.querySelectorAll('button'))
}

function bodyCloseButton(): HTMLButtonElement | null {
  return document.body.querySelector('.n-card-header__close')
}

let wrapper: VueWrapper | null = null

function mountModal() {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  wrapper = mount(StudioRedesignModal, {
    props: { show: true, projectId: 'studio_1' },
    global: { plugins: [i18n] },
    attachTo: document.body,
  })
  return wrapper
}

describe('StudioRedesignModal', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = null
    document.body.innerHTML = ''
  })

  it('renders the feedback textarea and title', () => {
    mountModal()
    expect(document.body.textContent).toContain('Redesign team & flow')
    expect(document.body.querySelector('textarea')).not.toBeNull()
  })

  it('shows a validation error and does not call startForge when feedback is empty', async () => {
    mountModal()
    const redesignBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Redesign')
    await redesignBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(startForge).not.toHaveBeenCalled()
    expect(document.body.textContent).toContain('Enter feedback describing the change')
  })

  it('shows a validation error for forbidden characters without calling startForge', async () => {
    mountModal()
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = 'add a reviewer; then ship'
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const redesignBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Redesign')
    await redesignBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(startForge).not.toHaveBeenCalled()
    expect(document.body.textContent).toContain('not allowed')
  })

  it('starts the redesign SSE run with the trimmed feedback and shows success on completion', async () => {
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_1' })
    vi.mocked(streamForgeEvents).mockImplementation((_runId, onEvent, onDone) => {
      onEvent({ event: 'forge.stdout', line: '[studio] redesigning...' })
      onDone({ exit_code: 0, duration_ms: 10 })
      return { abort: vi.fn() }
    })

    mountModal()
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = '  add a QA reviewer  '
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const redesignBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Redesign')
    await redesignBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(startForge).toHaveBeenCalledWith('studio_1', 'studio', ['redesign', 'add a QA reviewer'])
    expect(wrapper?.emitted('redesigned')).toHaveLength(1)
    expect(document.body.textContent).toContain('Redesign complete')
  })

  it('keeps the modal open and does not abort the stream when X-close is clicked while running', async () => {
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_2' })
    const abortMock = vi.fn()
    // Never invokes onEvent/onDone/onError — simulates a still-streaming run.
    vi.mocked(streamForgeEvents).mockReturnValue({ abort: abortMock })

    mountModal()
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = 'add a QA reviewer'
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const redesignBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Redesign')
    await redesignBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    const closeBtn = bodyCloseButton()
    expect(closeBtn).not.toBeNull()
    await closeBtn?.dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()

    expect(abortMock).not.toHaveBeenCalled()
    expect(wrapper?.emitted('update:show')).toBeUndefined()
  })

  it('aborts the live stream on unmount even if the run never finished (no EventSource leak)', async () => {
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_3' })
    const abortMock = vi.fn()
    vi.mocked(streamForgeEvents).mockReturnValue({ abort: abortMock })

    mountModal()
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = 'add a QA reviewer'
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const redesignBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Redesign')
    await redesignBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    wrapper?.unmount()
    wrapper = null
    expect(abortMock).toHaveBeenCalledTimes(1)
  })
})
