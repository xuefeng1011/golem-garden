import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import StudioCreateModal from '@/components/hermes/studio/StudioCreateModal.vue'
import { createStudio, fetchStudioPresets } from '@/api/hermes/studios'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'

const { messageMock, routerPushMock } = vi.hoisted(() => ({
  messageMock: { success: vi.fn(), warning: vi.fn(), error: vi.fn(), info: vi.fn() },
  routerPushMock: vi.fn(),
}))

vi.mock('@/api/hermes/studios', () => ({
  createStudio: vi.fn(),
  fetchStudioPresets: vi.fn(),
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

function bodyModeCards(): HTMLDivElement[] {
  return Array.from(document.body.querySelectorAll('.mode-card'))
}

function clickModeCard(label: string) {
  const card = bodyModeCards().find((c) => c.textContent?.includes(label))
  card?.dispatchEvent(new Event('click', { bubbles: true }))
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
    // Default: no presets — keeps the ①③-only fallback path unless a test overrides it.
    vi.mocked(fetchStudioPresets).mockResolvedValue([])
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = null
    document.body.innerHTML = ''
  })

  it('renders the create form with name/path fields and the start-mode cards (no preset by default)', async () => {
    mountModal()
    await flushPromises()
    expect(document.body.textContent).toContain('New Flow Studio')
    expect(bodyInputs()).toHaveLength(2)
    // No goal textarea until "AI team design" is selected.
    expect(document.body.querySelector('textarea')).toBeNull()
    expect(document.body.textContent).toContain('Empty studio')
    expect(document.body.textContent).toContain('AI team design')
    // No presets resolved — the preset card must not render.
    expect(document.body.textContent).not.toContain('Team preset')
  })

  it('shows the preset mode card and its list once fetchStudioPresets resolves', async () => {
    vi.mocked(fetchStudioPresets).mockResolvedValue([
      { id: 'novel-team', name: 'Novel Team', description: 'Fiction writing team' },
    ])
    mountModal()
    await flushPromises()
    expect(document.body.textContent).toContain('Team preset')

    clickModeCard('Team preset')
    await flushPromises()
    expect(document.body.textContent).toContain('Novel Team')
    expect(document.body.textContent).toContain('Fiction writing team')
  })

  it('warns and does not call createStudio when name is empty', async () => {
    mountModal()
    await flushPromises()
    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()
    expect(createStudio).not.toHaveBeenCalled()
    expect(messageMock.warning).toHaveBeenCalled()
  })

  it('warns and does not call createStudio when path is empty', async () => {
    mountModal()
    await flushPromises()
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

  it('creates the studio with trimmed fields and advances to the design stage (AI team design mode)', async () => {
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_1',
      name: 'Test Studio',
      path: 'C:/x',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })

    mountModal()
    await flushPromises()
    const inputs = bodyInputs()
    inputs[0].value = '  Test Studio  '
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = '  C:/x  '
    inputs[1].dispatchEvent(new Event('input'))
    clickModeCard('AI team design')
    await flushPromises()
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

  it('skips the design offer hint when the blank mode is used (default)', async () => {
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_2',
      name: 'No Goal Studio',
      path: 'C:/y',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })

    mountModal()
    await flushPromises()
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

  it('warns and does not create when AI mode is selected but no goal is entered', async () => {
    mountModal()
    await flushPromises()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/x'
    inputs[1].dispatchEvent(new Event('input'))
    clickModeCard('AI team design')
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(createStudio).not.toHaveBeenCalled()
    expect(messageMock.warning).toHaveBeenCalled()
  })

  it('applies the selected preset via SSE right after create and shows "Open editor" on success', async () => {
    vi.mocked(fetchStudioPresets).mockResolvedValue([
      { id: 'novel-team', name: 'Novel Team', description: 'Fiction writing team' },
    ])
    vi.mocked(createStudio).mockResolvedValue({
      id: 'studio_preset_1',
      name: 'Preset Studio',
      path: 'C:/p',
      createdAt: '2026-01-01T00:00:00',
      kind: 'studio',
    })
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_preset_1' })
    vi.mocked(streamForgeEvents).mockImplementation((_runId, onEvent, onDone) => {
      onEvent({ event: 'forge.stdout', line: '[studio] applying preset...' })
      onDone({ exit_code: 0, duration_ms: 10 })
      return { abort: vi.fn() }
    })

    mountModal()
    await flushPromises()
    const inputs = bodyInputs()
    inputs[0].value = 'Preset Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/p'
    inputs[1].dispatchEvent(new Event('input'))
    clickModeCard('Team preset')
    await flushPromises()
    clickModeCard('Novel Team')
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(createStudio).toHaveBeenCalledWith('Preset Studio', 'C:/p', '')
    expect(startForge).toHaveBeenCalledWith('studio_preset_1', 'studio', ['preset', 'apply', 'novel-team'])
    expect(document.body.textContent).toContain('Preset applied')
    expect(document.body.textContent).toContain('Open editor')
  })

  it('warns and does not create when preset mode is selected but no preset is chosen', async () => {
    vi.mocked(fetchStudioPresets).mockResolvedValue([
      { id: 'novel-team', name: 'Novel Team', description: 'Fiction writing team' },
    ])
    mountModal()
    await flushPromises()
    const inputs = bodyInputs()
    inputs[0].value = 'Preset Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/p'
    inputs[1].dispatchEvent(new Event('input'))
    clickModeCard('Team preset')
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(createStudio).not.toHaveBeenCalled()
    expect(messageMock.warning).toHaveBeenCalled()
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
    await flushPromises()
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
    await flushPromises()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/x'
    inputs[1].dispatchEvent(new Event('input'))
    clickModeCard('AI team design')
    await flushPromises()
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
    await flushPromises()
    const inputs = bodyInputs()
    inputs[0].value = 'Test Studio'
    inputs[0].dispatchEvent(new Event('input'))
    inputs[1].value = 'C:/x'
    inputs[1].dispatchEvent(new Event('input'))
    clickModeCard('AI team design')
    await flushPromises()
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
