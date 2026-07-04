import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import en from '@/i18n/locales/en'
import RunPanel from '@/components/hermes/flow-editor/RunPanel.vue'
import type { FlowLogSection } from '@/utils/flow-run-log'

function mountPanel(props: {
  lines?: string[]
  sections?: FlowLogSection[]
  currentStepId?: string | null
  running?: boolean
  phase?: 'idle' | 'running' | 'waiting' | 'done' | 'failed'
}) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(RunPanel, {
    props: {
      lines: props.lines ?? [],
      sections: props.sections ?? [],
      currentStepId: props.currentStepId ?? null,
      running: props.running ?? false,
      phase: props.phase ?? 'idle',
      waitingSteps: [],
    },
    global: { plugins: [i18n] },
  })
}

function makeSections(): FlowLogSection[] {
  return [
    {
      kind: 'step',
      stepId: 'step_1',
      soul: 'nova',
      title: 'Design the feature',
      lines: ['designing...'],
      status: 'done',
    },
    {
      kind: 'step',
      stepId: 'step_2',
      soul: 'ryn',
      title: 'Implement the feature',
      lines: ['implementing...'],
      status: 'running',
    },
  ]
}

describe('RunPanel', () => {
  it('renders one collapsible section per step with id and soul', () => {
    const wrapper = mountPanel({ sections: makeSections(), running: true, currentStepId: 'step_2' })
    const sections = wrapper.findAll('.log-section')
    expect(sections).toHaveLength(2)
    expect(sections[0].find('.section-title').text()).toContain('step_1')
    expect(sections[0].find('.section-title').text()).toContain('nova')
    expect(sections[1].find('.section-title').text()).toContain('step_2')
  })

  it('keeps the current running section open and collapses the finished one', () => {
    const wrapper = mountPanel({ sections: makeSections(), running: true, currentStepId: 'step_2' })
    const sections = wrapper.findAll('.log-section')
    // Finished step_1 auto-collapses (no manual override) — v-show sets display:none.
    expect(sections[0].find('.section-body').attributes('style')).toContain('display: none')
    // Running step_2 stays open — no display override.
    expect(sections[1].find('.section-body').attributes('style')).toBeUndefined()
  })

  it('toggling a section header overrides the auto open/collapse rule', async () => {
    const wrapper = mountPanel({ sections: makeSections(), running: true, currentStepId: 'step_2' })
    const headers = wrapper.findAll('.section-header')
    await headers[0].trigger('click')
    expect(wrapper.findAll('.log-section')[0].find('.section-body').attributes('style')).toBeUndefined()
  })

  it('shows the sticky current-step bar while running', () => {
    const wrapper = mountPanel({ sections: makeSections(), running: true, currentStepId: 'step_2' })
    expect(wrapper.find('.current-step-bar').text()).toContain('step_2')
    expect(wrapper.find('.current-step-bar').text()).toContain('ryn')
  })

  it('falls back to the raw log view when toggled', async () => {
    const wrapper = mountPanel({
      lines: ['raw line 1', 'raw line 2'],
      sections: makeSections(),
      running: true,
    })
    const rawToggle = wrapper.findAll('.view-toggle button')[1]
    await rawToggle.trigger('click')
    expect(wrapper.find('.run-log').exists()).toBe(true)
    expect(wrapper.findAll('.run-log .log-line')).toHaveLength(2)
  })

  it('renders a single unnamed section for legacy no-marker output', () => {
    const legacySection: FlowLogSection[] = [
      { kind: 'run', lines: ['plain output'], status: 'running' },
    ]
    const wrapper = mountPanel({ sections: legacySection, running: true })
    const sections = wrapper.findAll('.log-section')
    expect(sections).toHaveLength(1)
    expect(sections[0].find('.section-body').attributes('style')).toBeUndefined()
  })
})
