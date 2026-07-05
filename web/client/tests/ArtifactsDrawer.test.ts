import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, type VueWrapper } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import ArtifactsDrawer from '@/components/hermes/studio/ArtifactsDrawer.vue'
import { fetchArtifacts, fetchArtifactContent } from '@/api/hermes/artifacts'
import type { ArtifactContent } from '@/api/hermes/artifacts'

vi.mock('@/api/hermes/artifacts', () => ({
  fetchArtifacts: vi.fn(),
  fetchArtifactContent: vi.fn(),
}))

// NDrawer teleports its content to document.body, so it lands outside the
// mounted wrapper's own element tree — query the live DOM directly instead
// of wrapper.find()/text() (mirrors StudioCreateModal.test.ts).
function bodyText(): string {
  return document.body.textContent ?? ''
}

function bodyItems(): HTMLElement[] {
  return Array.from(document.body.querySelectorAll('.artifact-item'))
}

let wrapper: VueWrapper | null = null

function mountDrawer(props: { show?: boolean; projectId?: string; dir?: string } = {}) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  wrapper = mount(ArtifactsDrawer, {
    props: {
      show: props.show ?? true,
      projectId: props.projectId ?? 'studio_1',
      dir: props.dir,
    },
    global: { plugins: [i18n] },
    attachTo: document.body,
  })
  return wrapper
}

describe('ArtifactsDrawer', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  afterEach(() => {
    wrapper?.unmount()
    wrapper = null
    document.body.innerHTML = ''
  })

  it('fetches and renders the artifact list when opened (name, dir, size, mtime)', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([
      { path: 'reports/summary.md', name: 'summary.md', size: 2048, mtime: '2026-07-05T00:00:00' },
      { path: 'result.txt', name: 'result.txt', size: 10, mtime: '2026-07-04T00:00:00' },
    ])

    mountDrawer()
    await flushPromises()

    expect(fetchArtifacts).toHaveBeenCalledWith('studio_1', 'output')
    const items = bodyItems()
    expect(items).toHaveLength(2)
    expect(items[0].textContent).toContain('summary.md')
    expect(items[0].textContent).toContain('reports')
    expect(items[0].textContent).toContain('2.0 KB')
    expect(items[1].textContent).toContain('result.txt')
    expect(items[1].textContent).toContain('10 B')
  })

  it('shows the empty state when there are no artifacts', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([])
    mountDrawer()
    await flushPromises()
    expect(bodyText()).toContain('No artifacts yet')
  })

  it('shows an error state when the list fetch fails', async () => {
    vi.mocked(fetchArtifacts).mockRejectedValue(new Error('network down'))
    mountDrawer()
    await flushPromises()
    expect(bodyText()).toContain('network down')
  })

  it('clicking an artifact loads and displays its text content', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([
      { path: 'reports/summary.md', name: 'summary.md', size: 2048, mtime: '2026-07-05T00:00:00' },
    ])
    vi.mocked(fetchArtifactContent).mockResolvedValue({
      path: 'reports/summary.md',
      content: 'hello world',
      truncated: false,
      binary: false,
      size: 11,
    })

    mountDrawer()
    await flushPromises()

    const item = bodyItems()[0]
    await item.dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()

    expect(fetchArtifactContent).toHaveBeenCalledWith('studio_1', 'reports/summary.md')
    expect(document.body.querySelector('.content-viewer')?.textContent).toContain('hello world')
  })

  it('shows a truncated notice when content is truncated', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([
      { path: 'log.txt', name: 'log.txt', size: 999999, mtime: '2026-07-05T00:00:00' },
    ])
    vi.mocked(fetchArtifactContent).mockResolvedValue({
      path: 'log.txt',
      content: 'partial...',
      truncated: true,
      binary: false,
      size: 999999,
    })

    mountDrawer()
    await flushPromises()
    await bodyItems()[0].dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()

    expect(bodyText()).toContain('Content truncated')
  })

  it('shows a binary notice instead of raw content for binary artifacts', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([
      { path: 'image.png', name: 'image.png', size: 5000, mtime: '2026-07-05T00:00:00' },
    ])
    vi.mocked(fetchArtifactContent).mockResolvedValue({
      path: 'image.png',
      content: '',
      truncated: false,
      binary: true,
      size: 5000,
    })

    mountDrawer()
    await flushPromises()
    await bodyItems()[0].dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()

    expect(bodyText()).toContain('Preview unavailable')
    expect(document.body.querySelector('.content-viewer')).toBeNull()
  })

  it('the back button returns from the viewer pane to the list', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([
      { path: 'a.txt', name: 'a.txt', size: 1, mtime: '2026-07-05T00:00:00' },
    ])
    vi.mocked(fetchArtifactContent).mockResolvedValue({
      path: 'a.txt',
      content: 'a',
      truncated: false,
      binary: false,
      size: 1,
    })

    mountDrawer()
    await flushPromises()
    await bodyItems()[0].dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()
    expect(document.body.querySelector('.content-viewer')).not.toBeNull()

    const backBtn = Array.from(document.body.querySelectorAll('button')).find((b) =>
      b.textContent?.includes('Back to list'),
    )
    await backBtn?.dispatchEvent(new Event('click'))
    await flushPromises()

    expect(document.body.querySelector('.content-viewer')).toBeNull()
    expect(bodyItems()).toHaveLength(1)
  })

  it('exposes refresh() so callers can re-fetch after a run completes', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([])
    mountDrawer()
    await flushPromises()
    expect(fetchArtifacts).toHaveBeenCalledTimes(1)

    await (wrapper as unknown as { vm: { refresh: () => Promise<void> } }).vm.refresh()
    expect(fetchArtifacts).toHaveBeenCalledTimes(2)
  })

  it('a slow first click does not clobber a fast second click (generation-token guard)', async () => {
    vi.mocked(fetchArtifacts).mockResolvedValue([
      { path: 'a.txt', name: 'a.txt', size: 1, mtime: '2026-07-05T00:00:00' },
      { path: 'b.txt', name: 'b.txt', size: 1, mtime: '2026-07-05T00:00:00' },
    ])

    let resolveA: ((v: ArtifactContent) => void) | null = null
    vi.mocked(fetchArtifactContent).mockImplementation((_projectId, path) => {
      if (path === 'a.txt') {
        return new Promise((resolve) => {
          resolveA = resolve
        })
      }
      return Promise.resolve({ path: 'b.txt', content: 'content B', truncated: false, binary: false, size: 9 })
    })

    mountDrawer()
    await flushPromises()

    const items = bodyItems()
    // Click A first (its fetch stays pending), then click B (resolves immediately).
    await items[0].dispatchEvent(new Event('click', { bubbles: true }))
    await items[1].dispatchEvent(new Event('click', { bubbles: true }))
    await flushPromises()

    expect(document.body.querySelector('.content-viewer')?.textContent).toContain('content B')

    // A's delayed response arrives after B is already displayed — must not overwrite it.
    resolveA?.({ path: 'a.txt', content: 'content A', truncated: false, binary: false, size: 9 })
    await flushPromises()

    expect(document.body.querySelector('.content-viewer')?.textContent).toContain('content B')
    expect(document.body.querySelector('.content-viewer')?.textContent).not.toContain('content A')
  })
})
