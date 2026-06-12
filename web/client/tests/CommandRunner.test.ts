import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createI18n } from 'vue-i18n'
import CommandRunner from '@/components/hermes/forge/CommandRunner.vue'
import { getArgSchema } from '@/components/hermes/forge/commandSchema'
import en from '@/i18n/locales/en'

function mountRunner(command: string) {
  const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } })
  return mount(CommandRunner, {
    props: {
      command,
      description: '',
      argSchema: getArgSchema(command),
      running: false,
    },
    global: { plugins: [i18n] },
  })
}

function runButton(wrapper: ReturnType<typeof mountRunner>) {
  return wrapper.findAll('button').find((b) => b.text() === 'Run')!
}

describe('commandSchema', () => {
  it('marks no-arg commands as not accepting args', () => {
    expect(getArgSchema('status').allowsArgs).toBe(false)
    expect(getArgSchema('souls').allowsArgs).toBe(false)
  })

  it('declares required args for build/quick/assign', () => {
    expect(getArgSchema('build').required).toEqual(['task'])
    expect(getArgSchema('quick').required).toEqual(['task'])
    expect(getArgSchema('assign').required).toEqual(['soul', 'task'])
  })

  it('falls back to optional args for unknown commands', () => {
    expect(getArgSchema('does-not-exist')).toEqual({ required: [], allowsArgs: true })
  })
})

describe('CommandRunner arg gating', () => {
  it('hides the args section for no-arg commands and allows running', () => {
    const wrapper = mountRunner('status')
    expect(wrapper.find('.args-section').exists()).toBe(false)
    expect(wrapper.find('.no-args-note').exists()).toBe(true)
    expect(runButton(wrapper).attributes('disabled')).toBeUndefined()
  })

  it('disables run and shows a hint while required args are missing', () => {
    const wrapper = mountRunner('assign')
    expect(wrapper.find('.args-section').exists()).toBe(true)
    expect(runButton(wrapper).attributes('disabled')).toBeDefined()
    expect(wrapper.find('.required-hint').text()).toContain('soul')
    expect(wrapper.find('.required-hint').text()).toContain('task')
  })

  it('enables run once all required args are filled', async () => {
    const wrapper = mountRunner('assign')
    const inputs = wrapper.findAll('input')
    expect(inputs.length).toBe(2)
    await inputs[0].setValue('iron')
    await inputs[1].setValue('fix the build')
    expect(runButton(wrapper).attributes('disabled')).toBeUndefined()
    expect(wrapper.find('.required-hint').exists()).toBe(false)
  })

  it('emits run with no args for no-arg commands', async () => {
    const wrapper = mountRunner('status')
    await runButton(wrapper).trigger('click')
    expect(wrapper.emitted('run')).toEqual([[[]]])
  })

  it('does not emit run when required args are missing', async () => {
    const wrapper = mountRunner('build')
    await runButton(wrapper).trigger('click')
    expect(wrapper.emitted('run')).toBeUndefined()
  })
})
