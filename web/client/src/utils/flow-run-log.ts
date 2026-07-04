/**
 * flow-run-log.ts — Pure, incremental parser for Flow Engine run output.
 *
 * The engine interleaves raw agent stdout with marker lines of the form:
 *   [FLOW][RUN][<flow_id>] 시작 (steps=<N>)
 *   [FLOW][STEP][<step_id>][<soul|HOST|INPUT>] 시작: <task 앞 80자>
 *   [FLOW][STEP][<step_id>] 완료
 *   [FLOW][STEP][<step_id>] 실패: <사유>
 *   [FLOW][RUN][<flow_id>] 완료 / 실패
 *
 * feedFlowLogLine() folds one line at a time into an immutable FlowLogState —
 * suitable for driving both a grouped run-panel view and a live "current step"
 * indicator on the canvas. Lines that don't match the marker format are
 * attributed to the most recently started step (or a run preamble bucket).
 */

export interface FlowLogSection {
  kind: 'run' | 'step'
  stepId?: string
  soul?: string
  title?: string
  lines: string[]
  status: 'running' | 'done' | 'failed'
}

export interface FlowLogState {
  sections: FlowLogSection[]
  currentStepId: string | null
}

const MARKER_RE = /^\[FLOW\]\[(RUN|STEP)\]\[([^\]]+)\](?:\[([^\]]+)\])?\s*(.*)$/

export function createFlowLogState(): FlowLogState {
  return { sections: [], currentStepId: null }
}

function findLastStepSectionIndex(sections: FlowLogSection[], stepId: string): number {
  for (let i = sections.length - 1; i >= 0; i--) {
    if (sections[i].kind === 'step' && sections[i].stepId === stepId) return i
  }
  return -1
}

// Preamble bucket for lines seen before any [FLOW][STEP] start marker (run intro,
// legacy no-marker output). Reuses the trailing preamble section if one is open.
function ensurePreamble(sections: FlowLogSection[]): { sections: FlowLogSection[]; index: number } {
  const last = sections[sections.length - 1]
  if (last && last.kind === 'run') {
    return { sections, index: sections.length - 1 }
  }
  const preamble: FlowLogSection = { kind: 'run', lines: [], status: 'running' }
  return { sections: [...sections, preamble], index: sections.length }
}

function appendLineAt(sections: FlowLogSection[], index: number, line: string): FlowLogSection[] {
  return sections.map((s, i) => (i === index ? { ...s, lines: [...s.lines, line] } : s))
}

/**
 * feedFlowLogLine — fold a single output line into the state, returning a new
 * FlowLogState (no mutation). Call repeatedly as lines stream in.
 */
export function feedFlowLogLine(state: FlowLogState, line: string): FlowLogState {
  const match = line.match(MARKER_RE)

  if (!match) {
    const openIdx = state.currentStepId
      ? findLastStepSectionIndex(state.sections, state.currentStepId)
      : -1
    if (openIdx >= 0) {
      return { ...state, sections: appendLineAt(state.sections, openIdx, line) }
    }
    const { sections, index } = ensurePreamble(state.sections)
    return { ...state, sections: appendLineAt(sections, index, line) }
  }

  const [, type, id, soulOrKind, restRaw] = match
  const rest = restRaw.trim()

  if (type === 'RUN') {
    if (rest.startsWith('시작')) {
      const { sections } = ensurePreamble(state.sections)
      return { ...state, sections }
    }
    // 완료 | 실패 — run terminal marker: finalize any sections still "running".
    const finalStatus: 'done' | 'failed' = rest.startsWith('실패') ? 'failed' : 'done'
    const sections = state.sections.map((s) =>
      s.status === 'running' ? { ...s, status: finalStatus } : s,
    )
    return { sections, currentStepId: null }
  }

  // type === 'STEP'
  const stepId = id
  if (soulOrKind !== undefined) {
    // Start marker: [FLOW][STEP][id][soul|HOST|INPUT] 시작: <preview>
    const title = rest.replace(/^시작:\s*/, '')
    const section: FlowLogSection = {
      kind: 'step',
      stepId,
      soul: soulOrKind,
      title,
      lines: [],
      status: 'running',
    }
    return { sections: [...state.sections, section], currentStepId: stepId }
  }

  // Completion marker: 완료 | 실패: <사유>
  const idx = findLastStepSectionIndex(state.sections, stepId)
  const failed = rest.startsWith('실패')
  const status: 'done' | 'failed' = failed ? 'failed' : 'done'
  const sections =
    idx >= 0
      ? state.sections.map((s, i) =>
          i === idx ? { ...s, status, lines: failed ? [...s.lines, rest] : s.lines } : s,
        )
      : state.sections
  const currentStepId = state.currentStepId === stepId ? null : state.currentStepId
  return { sections, currentStepId }
}

/**
 * parseFlowLog — convenience bulk parse (reduces feedFlowLogLine over all lines).
 * Feeding lines one at a time as they stream in produces the same result.
 */
export function parseFlowLog(lines: string[]): FlowLogState {
  return lines.reduce(feedFlowLogLine, createFlowLogState())
}
