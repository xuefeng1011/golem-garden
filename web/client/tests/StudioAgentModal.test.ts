import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import { NSelect } from 'naive-ui'
import en from '@/i18n/locales/en'
import StudioAgentModal from '@/components/hermes/studio/StudioAgentModal.vue'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'

vi.mock('@/api/hermes/forge', () => ({
  startForge: vi.fn(),
  streamForgeEvents: vi.fn(),
}))

function bodyButtons(): HTMLButtonElement[] {
  return Array.from(document.body.querySelectorAll('button'))
}

function bodyInputs(): HTMLInputElement[] {
  return Array.from(document.body.querySelectorAll('input'))
}

function bodyTextareas(): HTMLTextAreaElement[] {
  return Array.from(document.body.querySelectorAll('textarea'))
}

let wrapper: VueWrapper | null = null

function mountModal() {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  wrapper = mount(StudioAgentModal, {
    props: { show: true, projectId: 'studio_1' },
    global: { plugins: [i18n] },
    attachTo: document.body,
  })
  return wrapper
}

// Fills name + role (required fields), leaves rules empty (default '' placeholder).
// name/role are plain NInput (<input>); rules is the only NInput type="textarea".
function fillRequiredFields() {
  const inputs = bodyInputs()
  inputs[0].value = 'researcher'
  inputs[0].dispatchEvent(new Event('input'))
  inputs[1].value = 'Researches things'
  inputs[1].dispatchEvent(new Event('input'))
}

describe('StudioAgentModal — args shape (rank/effort)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(startForge).mockResolvedValue({ run_id: 'run_1' })
    vi.mocked(streamForgeEvents).mockReturnValue({ abort: vi.fn() })
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = null
    document.body.innerHTML = ''
  })

  it('renders rank and effort selects with novice/not-specified defaults', () => {
    mountModal()
    expect(document.body.textContent).toContain('Rank')
    expect(document.body.textContent).toContain('Effort Level')
  })

  it('sends agent-add with rank=novice and effort="" placeholder when rules are left empty', async () => {
    mountModal()
    fillRequiredFields()
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(startForge).toHaveBeenCalledWith('studio_1', 'studio', [
      'agent-add',
      'researcher',
      'sonnet',
      'Researches things',
      '',
      'novice',
      '',
    ])
  })

  it('sends the selected rank/effort values when changed from their defaults', async () => {
    mountModal()
    fillRequiredFields()
    await flushPromises()

    // Template order: model select (0), rank select (1), effort select (2).
    const selects = wrapper!.findAllComponents(NSelect)
    expect(selects).toHaveLength(3)
    await selects[1].vm.$emit('update:value', 'expert')
    await selects[2].vm.$emit('update:value', 'high')
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(startForge).toHaveBeenCalledWith('studio_1', 'studio', [
      'agent-add',
      'researcher',
      'sonnet',
      'Researches things',
      '',
      'expert',
      'high',
    ])
  })

  it('passes non-empty trimmed rules through positionally ahead of rank/effort', async () => {
    mountModal()
    fillRequiredFields()
    const rulesTextarea = bodyTextareas()[0]
    rulesTextarea.value = '  Always cite sources  '
    rulesTextarea.dispatchEvent(new Event('input'))
    await flushPromises()

    const createBtn = bodyButtons().find((b) => b.textContent?.trim() === 'Create')
    await createBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(startForge).toHaveBeenCalledWith('studio_1', 'studio', [
      'agent-add',
      'researcher',
      'sonnet',
      'Researches things',
      'Always cite sources',
      'novice',
      '',
    ])
  })
})
