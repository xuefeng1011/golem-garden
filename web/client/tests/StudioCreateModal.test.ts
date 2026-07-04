import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import StudioCreateModal from '@/components/hermes/studio/StudioCreateModal.vue'
import { createStudio } from '@/api/hermes/studios'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'

const { messageMock, routerPushMock } = vi.hoisted(() => ({
  messageMock: { success: vi.fn(), warning: vi.fn(), error: vi.fn(), info: vi.fn() },
  routerPushMock: vi.fn(),
}))

vi.mock('@/api/hermes/studios', () => ({
  createStudio: vi.fn(),
}))

vi.mock('@/api/hermes/forge', () => ({
  startForge: vi.fn(),
  streamForgeEvents: vi.fn(),
}))

vi.mock('naive-ui', async () => {
  const actual = await vi.importActual<typeof import('naive-ui')>('naive-ui')
  return { ...actual, useMessage: () => messageMock }
})

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: routerPushMock }),
}))

// NModal teleports its content to document.body, so it lands outside the
// mounted wrapper's own element tree — query the live DOM directly instead
// of wrapper.find()/text() (which only walk wrapper.element's subtree).
function bodyButtons(): HTMLButtonElement[] {
  return Array.from(document.body.querySelectorAll('button'))
}

function bodyInputs(): HTMLInputElement[] {
  return Array.from(document.body.querySelectorAll('input'))
}

// NCard's built-in X close button (rendered by NModal preset="card").
function bodyCloseButton(): HTMLButtonElement | null {
  return document.body.querySelector('.n-card-header__close')
}

let wrapper: VueWrapper | null = null

function mountModal() {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  wrapper = mount(StudioCreateModal, {
    global: { plugins: [i18n] },
    attachTo: document.body,
  })
  return wrapper
}

describe('StudioCreateModal', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = null
    document.body.innerHTML = ''
  })

  it('renders the create form with name/path/goal fields', () => {
    mountModal()
    expect(document.body.textContent).toContain('New Flow Studio')
    expect(bodyInputs()).toHaveLength(2)
    expect(document.body.querySelector('textarea')).not.toBeNull()
  })

  it('warns and does not call createStudio when name is empty', async () => {
    mountModal()
    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()
    expect(createStudio).not.toHaveBeenCalled()
    expect(messageMock.warning).toHaveBeenCalled()
  })

  it('warns and does not call createStudio when path is empty', async () => {
    mountModal()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()
    expect(createStudio).not.toHaveBeenCalled()
    expect(messageMock.warning).toHaveBeenCalled()
  })

  it('creates the studio with trimmed fields and advances to the design stage', async () => {
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_1',
      name: 'Test Studio',
      path: 'C:/x',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })

    mountModal()
    const inputs = bodyInputs()
    inputs[0].value = '  Test Studio  '
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = '  C:/x  '
    inputs[1].dispatchEvent(new Event('input'))
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = '  Grow the garden  '
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(createStudio).toHaveBeenCalledWith('Test Studio', 'C:/x', 'Grow the garden')
    expect(wrapper?.emitted('created')).toHaveLength(1)
    // Stage 2: design run offer (goal was provided)
    expect(document.body.textContent).toContain('Generate AI team')
    expect(document.body.textContent).toContain('Just open it')
  })

  it('skips the design offer hint when no goal is entered', async () => {
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_2',
      name: 'No Goal Studio',
      path: 'C:/y',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })

    mountModal()
    const inputs = bodyInputs()
    inputs[0].value = 'No Goal Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/y'
    inputs[1].dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(createStudio).toHaveBeenCalledWith('No Goal Studio', 'C:/y', '')
    expect(document.body.textContent).toContain('No goal entered')
  })

  it('does not call createStudio twice on double-submit', async () => {
    let resolveCreate: (v: {
      id: string
      name: string
      path: string
      createdAt: string
      kind: 'studio'
    }) => void = () => {}
    vi.mocked(createStudio).mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveCreate = resolve
        }),
    )

    mountModal()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/x'
    inputs[1].dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(createStudio).toHaveBeenCalledTimes(1)
    resolveCreate({ id: 'studio_3', name: 'Test Studio', path: 'C:/x', createdAt: '2026-01-01T00:00:00', kind: 'studio' })
    await flushPromises()
  })

  it('keeps the modal open and does not abort the stream when X-close is clicked while a design run is active', async () => {
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_4',
      name: 'Test Studio',
      path: 'C:/x',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_1' })
    const abortMock = vi.fn()
    // Never invokes onEvent/onDone/onError — simulates a still-streaming run.
    vi.mocked(streamForgeEvents).mockReturnValue({ abort: abortMock })

    mountModal()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/x'
    inputs[1].dispatchEvent(new Event('input'))
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = 'Grow the garden'
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    const runBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Generate AI team')
    await runBtn?.dispatchEvent(new Event('click'))
    await flushPromises()
    expect(streamForgeEvents).toHaveBeenCalledTimes(1)

    // X-close while the design run is still streaming — must be a no-op.
    const closeBtn = bodyCloseButton()
    expect(closeBtn).not.toBeNull()
    await closeBtn?.dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()

    expect(abortMock).not.toHaveBeenCalled()
    expect(wrapper?.emitted('close')).toBeUndefined()
  })

  it('aborts the live design stream on unmount even if the run never finished (no EventSource leak)', async () => {
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_5',
      name: 'Test Studio',
      path: 'C:/x',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_2' })
    const abortMock = vi.fn()
    vi.mocked(streamForgeEvents).mockReturnValue({ abort: abortMock })

    mountModal()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/x'
    inputs[1].dispatchEvent(new Event('input'))
    const textarea = document.body.querySelector('textarea') as HTMLTextAreaElement
    textarea.value = 'Grow the garden'
    textarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    const runBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Generate AI team')
    await runBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    wrapper?.unmount()
    wrapper = null
    expect(abortMock).toHaveBeenCalledTimes(1)
  })
})
