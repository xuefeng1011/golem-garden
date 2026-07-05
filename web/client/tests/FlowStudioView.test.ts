import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import FlowStudioView from '@/views/hermes/FlowStudioView.vue'
import { fetchStudios, deleteStudio } from '@/api/hermes/studios'
import type { Studio } from '@/api/hermes/studios'

const { messageMock, dialogMock, routerPushMock } = vi.hoisted(() => ({
  messageMock: { success: vi.fn(), warning: vi.fn(), error: vi.fn(), info: vi.fn() },
  dialogMock: { warning: vi.fn() },
  routerPushMock: vi.fn(),
}))

vi.mock('@/api/hermes/studios', () => ({
  fetchStudios: vi.fn(),
  deleteStudio: vi.fn(),
}))

vi.mock('naive-ui', async () => {
  const actual = await vi.importActual<typeof import('naive-ui')>('naive-ui')
  return { ...actual, useMessage: () => messageMock, useDialog: () => dialogMock }
})

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: routerPushMock }),
}))

function makeStudio(overrides: Partial<Studio> = {}): Studio {
  return {
    id: 'studio_1',
    name: 'Test Studio',
    path: 'C:/x',
    createdAt: '2026-01-01T00:00:00',
    kind: 'studio',
    goal: '',
    ...overrides,
  }
}

let wrapper: VueWrapper | null = null

function mountView() {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  wrapper = mount(FlowStudioView, { global: { plugins: [i18n] } })
  return wrapper
}

// dialog.warning({ ... onPositiveClick }) — the last call's options.
function lastDialogOptions(): { title: string; content: string; onPositiveClick: () => unknown } {
  const call = dialogMock.warning.mock.calls.at(-1)
  return call?.[0]
}

describe('FlowStudioView — delete studio', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = null
  })

  it('opens a confirm dialog naming the studio and noting the disk is untouched', async () => {
    vi.mocked(fetchStudios).mockResolvedValue([makeStudio()])
    mountView()
    await flushPromises()

    const deleteBtn = wrapper!.findAll('button').find((b) => b.text() === 'Delete')
    expect(deleteBtn).toBeTruthy()
    await deleteBtn!.trigger('click')

    expect(dialogMock.warning).toHaveBeenCalledTimes(1)
    const opts = lastDialogOptions()
    expect(opts.title).toBe('Delete studio')
    expect(opts.content).toContain('Test Studio')
    expect(opts.content).toContain('stay on disk')
  })

  it('deletes and reloads the list on confirm, showing a success message', async () => {
    vi.mocked(fetchStudios).mockResolvedValue([makeStudio()])
    vi.mocked(deleteStudio).mockResolvedValue(undefined)
    mountView()
    await flushPromises()

    const deleteBtn = wrapper!.findAll('button').find((b) => b.text() === 'Delete')
    await deleteBtn!.trigger('click')
    await lastDialogOptions().onPositiveClick()
    await flushPromises()

    expect(deleteStudio).toHaveBeenCalledWith('studio_1')
    expect(messageMock.success).toHaveBeenCalled()
    expect(fetchStudios).toHaveBeenCalledTimes(2) // initial load + post-delete reload
  })

  it('shows an error message with the failure detail when deleteStudio rejects', async () => {
    vi.mocked(fetchStudios).mockResolvedValue([makeStudio()])
    vi.mocked(deleteStudio).mockRejectedValue(new Error('API Error 500: boom'))
    mountView()
    await flushPromises()

    const deleteBtn = wrapper!.findAll('button').find((b) => b.text() === 'Delete')
    await deleteBtn!.trigger('click')
    await lastDialogOptions().onPositiveClick()
    await flushPromises()

    expect(messageMock.error).toHaveBeenCalledTimes(1)
    expect(messageMock.error.mock.calls[0][0]).toContain('boom')
  })
})
