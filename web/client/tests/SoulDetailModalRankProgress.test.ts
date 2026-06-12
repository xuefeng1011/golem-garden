import { describe, it, expect, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import SoulDetailModal from '@/components/hermes/souls/SoulDetailModal.vue'
import RankProgress from '@/components/common/RankProgress.vue'
import en from '@/i18n/locales/en'
import type { SoulDetail, SoulActivity } from '@/api/hermes/souls'

const detail: SoulDetail = {
  id: 'nova',
  name: 'Nova',
  rank: 'junior',
  specialty: ['frontend'],
  description: 'Frontend specialist',
  content: '',
  tools: ['Read', 'Edit'],
  disallowed_tools: [],
  max_turns: null,
  isolation: 'none',
  is_coordinator: false,
  effort: null,
}

const activity: SoulActivity = {
  soul_id: 'nova',
  rank: 'junior',
  tasks_total: 12,
  tasks_success: 10,
  streak: 3,
  last_task_ts: '2026-06-01',
  recent_tasks: [{ task: 'Build dashboard', result: 'success', ts: '2026-06-01' }],
  rank_progress: { current: 'junior', next: 'senior', tasks_to_promote: 18 },
}

vi.mock('@/api/hermes/souls', () => ({
  fetchSoul: vi.fn(() => Promise.resolve(detail)),
  fetchSoulActivity: vi.fn(() => Promise.resolve(activity)),
  fetchSkillTree: vi.fn(() => Promise.resolve({ branches: [] })),
}))

function mountModal() {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(SoulDetailModal, {
    props: { projectId: 'p1', soulId: 'nova', open: true },
    global: {
      plugins: [i18n],
      stubs: {
        teleport: true,
        MarkdownRenderer: true,
      },
    },
  })
}

describe('SoulDetailModal rank progress integration', () => {
  it('renders the shared RankProgress component fed by activity rank_progress', async () => {
    const wrapper = mountModal()
    await flushPromises()

    const rank = wrapper.findComponent(RankProgress)
    expect(rank.exists()).toBe(true)
    expect(rank.props('current')).toBe('junior')
    expect(rank.props('next')).toBe('senior')
    expect(rank.props('tasksToPromote')).toBe(18)
    // caption comes from the shared component i18n keys
    expect(rank.text()).toContain('18 tasks to next rank')
  })

  it('shows activity counters and recent tasks section', async () => {
    const wrapper = mountModal()
    await flushPromises()

    const text = wrapper.text()
    expect(text).toContain('Total tasks')
    expect(text).toContain('12')
    expect(text).toContain('Recent tasks')
    expect(text).toContain('Build dashboard')
  })
})
