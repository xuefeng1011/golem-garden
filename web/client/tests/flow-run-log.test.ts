import { describe, it, expect } from 'vitest'
import {
  createFlowLogState,
  feedFlowLogLine,
  parseFlowLog,
} from '@/utils/flow-run-log'
import type { FlowLogState } from '@/utils/flow-run-log'

function feedAll(lines: string[]): FlowLogState {
  let state = createFlowLogState()
  for (const line of lines) {
    state = feedFlowLogLine(state, line)
  }
  return state
}

describe('flow-run-log', () => {
  it('groups a full run into a run preamble + per-step sections', () => {
    const lines = [
      '[FLOW][RUN][flow_1] 시작 (steps=2)',
      '[FLOW][STEP][step_1][commander] 시작: Design the feature',
      'some raw agent output line 1',
      'some raw agent output line 2',
      '[FLOW][STEP][step_1] 완료',
      '[FLOW][STEP][step_2][HOST] 시작: Implement the feature',
      'implementing...',
      '[FLOW][STEP][step_2] 완료',
      '[FLOW][RUN][flow_1] 완료',
    ]
    const state = parseFlowLog(lines)

    expect(state.sections).toHaveLength(3)
    const [preamble, step1, step2] = state.sections

    expect(preamble.kind).toBe('run')
    expect(preamble.lines).toEqual([])

    expect(step1.kind).toBe('step')
    expect(step1.stepId).toBe('step_1')
    expect(step1.soul).toBe('commander')
    expect(step1.title).toBe('Design the feature')
    expect(step1.status).toBe('done')
    expect(step1.lines).toEqual(['some raw agent output line 1', 'some raw agent output line 2'])

    expect(step2.kind).toBe('step')
    expect(step2.stepId).toBe('step_2')
    expect(step2.soul).toBe('HOST')
    expect(step2.status).toBe('done')
    expect(step2.lines).toEqual(['implementing...'])

    expect(state.currentStepId).toBeNull()
  })

  it('tracks currentStepId while a step is running and clears it on completion', () => {
    let state = createFlowLogState()

    state = feedFlowLogLine(state, '[FLOW][STEP][step_1][nova] 시작: Do the thing')
    expect(state.currentStepId).toBe('step_1')
    expect(state.sections[0].status).toBe('running')

    state = feedFlowLogLine(state, '[FLOW][STEP][step_1] 완료')
    expect(state.currentStepId).toBeNull()
    expect(state.sections[0].status).toBe('done')
  })

  it('captures the failure reason on a step and marks the run failed', () => {
    const lines = [
      '[FLOW][STEP][step_1][ryn] 시작: Risky task',
      'about to fail...',
      '[FLOW][STEP][step_1] 실패: timeout after 60s',
      '[FLOW][RUN][flow_1] 실패',
    ]
    const state = parseFlowLog(lines)
    expect(state.sections).toHaveLength(1)
    const step = state.sections[0]
    expect(step.status).toBe('failed')
    expect(step.lines).toEqual(['about to fail...', '실패: timeout after 60s'])
    expect(state.currentStepId).toBeNull()
  })

  it('finalizes any still-running sections when the run marker terminates', () => {
    // Engine aborted mid-step without emitting a per-step failure marker.
    const lines = [
      '[FLOW][STEP][step_1][nova] 시작: Long task',
      'partial output',
      '[FLOW][RUN][flow_1] 실패',
    ]
    const state = parseFlowLog(lines)
    expect(state.sections[0].status).toBe('failed')
    expect(state.currentStepId).toBeNull()
  })

  it('handles legacy output with no markers as a single unnamed section', () => {
    const lines = ['plain line one', 'plain line two', 'plain line three']
    const state = parseFlowLog(lines)
    expect(state.sections).toHaveLength(1)
    expect(state.sections[0].kind).toBe('run')
    expect(state.sections[0].stepId).toBeUndefined()
    expect(state.sections[0].lines).toEqual(lines)
  })

  it('attributes unmatched lines to the most recently started step', () => {
    const lines = [
      '[FLOW][STEP][step_1][nova] 시작: First',
      'line for step 1',
      '[FLOW][STEP][step_2][sage] 시작: Second',
      'line for step 2',
      'another line for step 2',
    ]
    const state = parseFlowLog(lines)
    expect(state.sections[0].lines).toEqual(['line for step 1'])
    expect(state.sections[1].lines).toEqual(['line for step 2', 'another line for step 2'])
  })

  it('produces the same result whether fed line-by-line or parsed in bulk', () => {
    const lines = [
      '[FLOW][RUN][flow_1] 시작 (steps=1)',
      '[FLOW][STEP][step_1][nova] 시작: Chunked task',
      'chunk a',
      'chunk b',
      '[FLOW][STEP][step_1] 완료',
      '[FLOW][RUN][flow_1] 완료',
    ]
    const bulk = parseFlowLog(lines)
    const incremental = feedAll(lines)
    expect(incremental).toEqual(bulk)
  })
})
