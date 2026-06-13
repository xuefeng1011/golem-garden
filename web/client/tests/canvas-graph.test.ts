import { describe, it, expect } from 'vitest'
import {
  buildExecutionFlow,
  buildMissionDag,
  buildSessionTree,
  buildTimeline,
  buildFlowDag,
  filterRunsByRange,
  layoutWithDagre,
  stepsFromGraph,
  editorGraphFromFlow,
} from '@/utils/canvas-graph'
import type { GraphNode, GraphEdge, EditorNodeData } from '@/utils/canvas-graph'
import type { RunMeta } from '@/api/hermes/console'
import type { MailboxMessage } from '@/api/hermes/souls'
import type { Mission } from '@/api/hermes/missions'
import type { Flow } from '@/api/hermes/flows'

// ── fixtures ──────────────────────────────────────────────────────────────────

function makeRun(overrides: Partial<RunMeta> = {}): RunMeta {
  return {
    run_id: 'run_001',
    session_id: 'sess_001',
    soul: 'ryn',
    model: 'claude-sonnet-4-5',
    source: 'bash',
    ts_start: '2026-06-13T00:00:00Z',
    duration_ms: 1200,
    tokens_in: 100,
    tokens_out: 200,
    tokens_cache: 0,
    cost_usd: 0.005,
    result: 'success',
    tool_counts: { Read: 2, Bash: 1 },
    ...overrides,
  }
}

function makeMission(overrides: Partial<Mission> = {}): Mission {
  return {
    id: 'msn_001',
    goal: 'Build the canvas view',
    status: 'completed',
    created: '2026-06-13T00:00:00Z',
    tasks: [
      { idx: 0, task: 'Plan layout', soul: 'nex', status: 'done' },
      { idx: 1, task: 'Implement graph', soul: 'ryn', status: 'done' },
      { idx: 2, task: 'Write tests', soul: 'ryn', status: 'done' },
    ],
    ...overrides,
  }
}

// ── layoutWithDagre ───────────────────────────────────────────────────────────

describe('layoutWithDagre', () => {
  it('returns empty array for empty input', () => {
    expect(layoutWithDagre([], [], 'TB')).toEqual([])
  })

  it('assigns non-zero positions to nodes', () => {
    const nodes = [
      { id: 'a', type: 'soul' as const, position: { x: 0, y: 0 }, data: { label: 'A', nodeType: 'soul' as const } },
      { id: 'b', type: 'run' as const, position: { x: 0, y: 0 }, data: { label: 'B', nodeType: 'run' as const } },
    ]
    const edges = [{ id: 'e1', source: 'a', target: 'b' }]
    const result = layoutWithDagre(nodes, edges, 'TB')
    expect(result).toHaveLength(2)
    // dagre should assign distinct y positions for TB layout
    const yA = result.find((n) => n.id === 'a')!.position.y
    const yB = result.find((n) => n.id === 'b')!.position.y
    expect(yB).toBeGreaterThan(yA)
  })

  it('returns nodes with position fields', () => {
    const nodes = [
      { id: 'x', type: 'soul' as const, position: { x: 0, y: 0 }, data: { label: 'X', nodeType: 'soul' as const } },
    ]
    const result = layoutWithDagre(nodes, [], 'LR')
    expect(result[0].position).toHaveProperty('x')
    expect(result[0].position).toHaveProperty('y')
  })

  it('ignores edges referencing missing nodes gracefully', () => {
    const nodes = [
      { id: 'a', type: 'soul' as const, position: { x: 0, y: 0 }, data: { label: 'A', nodeType: 'soul' as const } },
    ]
    const edges = [{ id: 'e1', source: 'a', target: 'missing' }]
    expect(() => layoutWithDagre(nodes, edges, 'TB')).not.toThrow()
  })
})

// ── buildExecutionFlow ────────────────────────────────────────────────────────

describe('buildExecutionFlow', () => {
  it('returns empty graph for empty input', () => {
    const { nodes, edges } = buildExecutionFlow([], [])
    expect(nodes).toHaveLength(0)
    expect(edges).toHaveLength(0)
  })

  it('creates one soul node per unique soul', () => {
    const runs = [
      makeRun({ soul: 'ryn', run_id: 'r1' }),
      makeRun({ soul: 'nex', run_id: 'r2' }),
      makeRun({ soul: 'ryn', run_id: 'r3' }),
    ]
    const { nodes } = buildExecutionFlow(runs, [])
    const soulNodes = nodes.filter((n) => n.data.nodeType === 'soul')
    expect(soulNodes).toHaveLength(2)
    const soulNames = soulNodes.map((n) => n.data.soul).sort()
    expect(soulNames).toEqual(['nex', 'ryn'])
  })

  it('soul node data contains only scalars (G7 compliance)', () => {
    const runs = [makeRun({ soul: 'ryn' })]
    const { nodes } = buildExecutionFlow(runs, [])
    const soulNode = nodes.find((n) => n.data.nodeType === 'soul')!
    for (const [, val] of Object.entries(soulNode.data)) {
      expect(typeof val).not.toBe('object')
    }
  })

  it('run node data contains only scalars (G7 compliance)', () => {
    const runs = [makeRun()]
    const { nodes } = buildExecutionFlow(runs, [])
    const runNode = nodes.find((n) => n.data.nodeType === 'run')!
    for (const [, val] of Object.entries(runNode.data)) {
      expect(typeof val).not.toBe('object')
    }
  })

  it('caps run child nodes at 10 per soul', () => {
    const runs = Array.from({ length: 15 }, (_, i) =>
      makeRun({ soul: 'ryn', run_id: `r${i}`, ts_start: `2026-06-13T0${String(i).padStart(1, '0')}:00:00Z` }),
    )
    const { nodes } = buildExecutionFlow(runs, [])
    const runNodes = nodes.filter((n) => n.data.nodeType === 'run')
    expect(runNodes.length).toBeLessThanOrEqual(10)
  })

  it('computes successRate correctly on soul node', () => {
    const runs = [
      makeRun({ soul: 'ryn', run_id: 'r1', result: 'success' }),
      makeRun({ soul: 'ryn', run_id: 'r2', result: 'error' }),
    ]
    const { nodes } = buildExecutionFlow(runs, [])
    const soulNode = nodes.find((n) => n.data.nodeType === 'soul')!
    expect(soulNode.data.successRate).toBe(50)
    expect(soulNode.data.runCount).toBe(2)
  })

  it('creates mailbox edge between soul nodes with count label', () => {
    const runs = [
      makeRun({ soul: 'ryn', run_id: 'r1' }),
      makeRun({ soul: 'nex', run_id: 'r2' }),
    ]
    const messages: MailboxMessage[] = [
      { from: 'ryn', to: 'nex', type: 'task_assign', content: 'task', ts: '2026-06-13T00:00:00Z' },
      { from: 'ryn', to: 'nex', type: 'task_done', content: 'done', ts: '2026-06-13T00:01:00Z' },
    ]
    const { edges } = buildExecutionFlow(runs, messages)
    const mailEdge = edges.find((e) => e.id.startsWith('mail__'))
    expect(mailEdge).toBeDefined()
    expect(mailEdge!.label).toBe('2')
  })

  it('skips mailbox edges for souls not in run set', () => {
    const runs = [makeRun({ soul: 'ryn', run_id: 'r1' })]
    const messages: MailboxMessage[] = [
      { from: 'ryn', to: 'ghost', type: 'info', content: 'x', ts: '2026-06-13T00:00:00Z' },
    ]
    const { edges } = buildExecutionFlow(runs, messages)
    const mailEdges = edges.filter((e) => e.id.startsWith('mail__'))
    expect(mailEdges).toHaveLength(0)
  })

  it('all nodes have position assigned by dagre', () => {
    const runs = [
      makeRun({ soul: 'ryn', run_id: 'r1' }),
      makeRun({ soul: 'nex', run_id: 'r2' }),
    ]
    const { nodes } = buildExecutionFlow(runs, [])
    for (const node of nodes) {
      expect(node.position).toHaveProperty('x')
      expect(node.position).toHaveProperty('y')
    }
  })
})

// ── buildMissionDag ───────────────────────────────────────────────────────────

describe('buildMissionDag', () => {
  it('creates a mission root node', () => {
    const mission = makeMission()
    const { nodes } = buildMissionDag(mission)
    const missionNode = nodes.find((n) => n.data.nodeType === 'mission')
    expect(missionNode).toBeDefined()
    expect(missionNode!.data.missionId).toBe('msn_001')
    expect(missionNode!.data.status).toBe('completed')
  })

  it('creates task nodes for each task', () => {
    const mission = makeMission()
    const { nodes } = buildMissionDag(mission)
    const taskNodes = nodes.filter((n) => n.data.nodeType === 'task')
    expect(taskNodes).toHaveLength(3)
  })

  it('tasks are connected in idx order', () => {
    const mission = makeMission()
    const { edges } = buildMissionDag(mission)
    // 1 mission->task0 + task0->task1 + task1->task2 = 3 edges
    expect(edges).toHaveLength(3)
  })

  it('handles mission with no tasks', () => {
    const mission = makeMission({ tasks: [] })
    const { nodes, edges } = buildMissionDag(mission)
    expect(nodes).toHaveLength(1)
    expect(edges).toHaveLength(0)
  })

  it('truncates long goal label', () => {
    const longGoal = 'A'.repeat(100)
    const mission = makeMission({ goal: longGoal })
    const { nodes } = buildMissionDag(mission)
    const missionNode = nodes.find((n) => n.data.nodeType === 'mission')!
    expect(missionNode.data.label.length).toBeLessThanOrEqual(63) // 60+3 for '…'
  })

  it('task nodes contain soul and status fields', () => {
    const mission = makeMission()
    const { nodes } = buildMissionDag(mission)
    const taskNode = nodes.find((n) => n.data.nodeType === 'task' && n.data.taskIdx === 0)!
    expect(taskNode.data.soul).toBe('nex')
    expect(taskNode.data.status).toBe('done')
  })

  it('all nodes have dagre-assigned positions', () => {
    const mission = makeMission()
    const { nodes } = buildMissionDag(mission)
    for (const node of nodes) {
      expect(typeof node.position.x).toBe('number')
      expect(typeof node.position.y).toBe('number')
    }
  })
})

// ── buildSessionTree ──────────────────────────────────────────────────────────

describe('buildSessionTree', () => {
  it('returns empty graph for empty runs', () => {
    const { nodes, edges } = buildSessionTree([])
    expect(nodes).toHaveLength(0)
    expect(edges).toHaveLength(0)
  })

  it('groups runs by session_id', () => {
    const runs = [
      makeRun({ session_id: 'sess_A', run_id: 'r1' }),
      makeRun({ session_id: 'sess_A', run_id: 'r2' }),
      makeRun({ session_id: 'sess_B', run_id: 'r3' }),
    ]
    const { nodes } = buildSessionTree(runs)
    const sessionNodes = nodes.filter((n) => n.data.nodeType === 'session')
    expect(sessionNodes).toHaveLength(2)
  })

  it('session node has childCount equal to run count', () => {
    const runs = [
      makeRun({ session_id: 'sess_A', run_id: 'r1' }),
      makeRun({ session_id: 'sess_A', run_id: 'r2' }),
    ]
    const { nodes } = buildSessionTree(runs)
    const sessionNode = nodes.find((n) => n.data.nodeType === 'session')!
    expect(sessionNode.data.childCount).toBe(2)
  })

  it('creates edges from session to run nodes', () => {
    const runs = [
      makeRun({ session_id: 'sess_A', run_id: 'r1' }),
      makeRun({ session_id: 'sess_A', run_id: 'r2' }),
    ]
    const { edges } = buildSessionTree(runs)
    expect(edges).toHaveLength(2)
    for (const edge of edges) {
      expect(edge.source).toBe('session__sess_A')
    }
  })
})

// ── 300-node synthetic stress test ───────────────────────────────────────────

describe('300-node synthetic stress test', () => {
  it('builds and lays out 300 nodes with dagre without errors', () => {
    // 30 souls × 10 runs each = 300 run nodes + 30 soul nodes = 330 nodes total
    const souls = Array.from({ length: 30 }, (_, i) => `soul_${i}`)
    const runs: RunMeta[] = []
    for (const soul of souls) {
      for (let r = 0; r < 10; r++) {
        runs.push(
          makeRun({
            soul,
            run_id: `run_${soul}_${r}`,
            session_id: `sess_${soul}`,
            result: r % 5 === 0 ? 'error' : 'success',
            cost_usd: 0.001 * r,
          }),
        )
      }
    }

    const { nodes, edges } = buildExecutionFlow(runs, [])

    // Should have 30 soul nodes + up to 300 run nodes
    expect(nodes.length).toBeGreaterThanOrEqual(30)
    expect(nodes.length).toBeLessThanOrEqual(330)

    // All nodes must have numeric positions assigned by dagre
    for (const node of nodes) {
      expect(typeof node.position.x).toBe('number')
      expect(typeof node.position.y).toBe('number')
      expect(Number.isFinite(node.position.x)).toBe(true)
      expect(Number.isFinite(node.position.y)).toBe(true)
    }

    // No node data field should be an object (G7)
    for (const node of nodes) {
      for (const [, val] of Object.entries(node.data)) {
        expect(typeof val).not.toBe('object')
      }
    }

    // Edges should all have valid source/target
    const nodeIds = new Set(nodes.map((n) => n.id))
    for (const edge of edges) {
      expect(nodeIds.has(edge.source)).toBe(true)
      expect(nodeIds.has(edge.target)).toBe(true)
    }
  })
})

// ── filterRunsByRange ─────────────────────────────────────────────────────────

describe('filterRunsByRange', () => {
  const now = Date.now()

  function makeTimedRun(hoursAgo: number, id: string): RunMeta {
    return makeRun({
      run_id: id,
      ts_start: new Date(now - hoursAgo * 60 * 60 * 1000).toISOString(),
    })
  }

  it('returns all runs for range "all"', () => {
    const runs = [makeTimedRun(200, 'r1'), makeTimedRun(10, 'r2')]
    expect(filterRunsByRange(runs, 'all')).toHaveLength(2)
  })

  it('filters to last 24h', () => {
    const runs = [makeTimedRun(25, 'old'), makeTimedRun(10, 'recent')]
    const result = filterRunsByRange(runs, '24h')
    expect(result).toHaveLength(1)
    expect(result[0].run_id).toBe('recent')
  })

  it('filters to last 7d', () => {
    const runs = [makeTimedRun(8 * 24, 'old'), makeTimedRun(3 * 24, 'recent')]
    const result = filterRunsByRange(runs, '7d')
    expect(result).toHaveLength(1)
    expect(result[0].run_id).toBe('recent')
  })

  it('returns empty array when no runs pass filter', () => {
    const runs = [makeTimedRun(200, 'r1')]
    expect(filterRunsByRange(runs, '24h')).toHaveLength(0)
  })
})

// ── buildTimeline ─────────────────────────────────────────────────────────────

describe('buildTimeline', () => {
  it('returns empty graph for empty runs', () => {
    const { nodes, edges } = buildTimeline([])
    expect(nodes).toHaveLength(0)
    expect(edges).toHaveLength(0)
  })

  it('places each soul on a distinct y-lane', () => {
    const runs = [
      makeRun({ soul: 'ryn', run_id: 'r1', ts_start: '2026-06-13T00:00:00Z', session_id: 'sa' }),
      makeRun({ soul: 'nex', run_id: 'r2', ts_start: '2026-06-13T00:01:00Z', session_id: 'sb' }),
    ]
    const { nodes } = buildTimeline(runs, 'all')
    const rynNode = nodes.find((n) => n.data.soul === 'ryn')!
    const nexNode = nodes.find((n) => n.data.soul === 'nex')!
    expect(rynNode.position.y).not.toBe(nexNode.position.y)
  })

  it('connects consecutive runs in the same session with edges', () => {
    const runs = [
      makeRun({ run_id: 'r1', ts_start: '2026-06-13T00:00:00Z', session_id: 'sess_x' }),
      makeRun({ run_id: 'r2', ts_start: '2026-06-13T00:01:00Z', session_id: 'sess_x' }),
      makeRun({ run_id: 'r3', ts_start: '2026-06-13T00:02:00Z', session_id: 'sess_x' }),
    ]
    const { edges } = buildTimeline(runs, 'all')
    // r1→r2 and r2→r3
    expect(edges).toHaveLength(2)
    expect(edges[0].source).toBe('tl__r1')
    expect(edges[0].target).toBe('tl__r2')
    expect(edges[1].source).toBe('tl__r2')
    expect(edges[1].target).toBe('tl__r3')
  })

  it('does not connect runs from different sessions', () => {
    const runs = [
      makeRun({ run_id: 'r1', ts_start: '2026-06-13T00:00:00Z', session_id: 'sess_a' }),
      makeRun({ run_id: 'r2', ts_start: '2026-06-13T00:01:00Z', session_id: 'sess_b' }),
    ]
    const { edges } = buildTimeline(runs, 'all')
    expect(edges).toHaveLength(0)
  })

  it('all node data fields are scalars (G7 compliance)', () => {
    const runs = [makeRun({ run_id: 'r1', ts_start: '2026-06-13T00:00:00Z' })]
    const { nodes } = buildTimeline(runs, 'all')
    for (const node of nodes) {
      for (const [, val] of Object.entries(node.data)) {
        expect(typeof val).not.toBe('object')
      }
    }
  })

  it('applies 24h range filter correctly', () => {
    const now = Date.now()
    const recent = new Date(now - 1 * 60 * 60 * 1000).toISOString()
    const old = new Date(now - 48 * 60 * 60 * 1000).toISOString()
    const runs = [
      makeRun({ run_id: 'r_old', ts_start: old }),
      makeRun({ run_id: 'r_new', ts_start: recent }),
    ]
    const { nodes } = buildTimeline(runs, '24h')
    expect(nodes).toHaveLength(1)
    expect(nodes[0].data.runId).toBe('r_new')
  })

  it('assigns timeIndex and soulIndex as scalars', () => {
    const runs = [
      makeRun({ soul: 'ryn', run_id: 'r1', ts_start: '2026-06-13T00:00:00Z' }),
      makeRun({ soul: 'nex', run_id: 'r2', ts_start: '2026-06-13T00:01:00Z' }),
    ]
    const { nodes } = buildTimeline(runs, 'all')
    for (const n of nodes) {
      expect(typeof n.data.timeIndex).toBe('number')
      expect(typeof n.data.soulIndex).toBe('number')
    }
  })
})

// ── buildFlowDag ──────────────────────────────────────────────────────────────

function makeFlow(overrides: Partial<Flow> = {}): Flow {
  return {
    flow_id: 'flow_001',
    goal: 'Deploy the feature',
    status: 'running',
    created: '2026-06-13T00:00:00Z',
    steps: [
      { id: 's1', soul: 'ryn', task: 'Build', deps: [], status: 'done', approval: false, on_fail: 'abort' },
      { id: 's2', soul: 'nex', task: 'Review', deps: ['s1'], status: 'waiting_approval', approval: true, on_fail: 'abort' },
      { id: 's3', soul: 'ryn', task: 'Deploy', deps: ['s2'], status: 'pending', approval: false, on_fail: 'continue' },
    ],
    ...overrides,
  }
}

describe('buildFlowDag', () => {
  it('returns empty graph for flow with no steps', () => {
    const flow = makeFlow({ steps: [] })
    const { nodes, edges } = buildFlowDag(flow)
    expect(nodes).toHaveLength(0)
    expect(edges).toHaveLength(0)
  })

  it('creates one node per step', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    expect(nodes).toHaveLength(3)
  })

  it('creates edges from deps (s1→s2, s2→s3)', () => {
    const flow = makeFlow()
    const { edges } = buildFlowDag(flow)
    expect(edges).toHaveLength(2)
    expect(edges.find((e) => e.source === 'fs__s1' && e.target === 'fs__s2')).toBeDefined()
    expect(edges.find((e) => e.source === 'fs__s2' && e.target === 'fs__s3')).toBeDefined()
  })

  it('ignores deps that reference non-existent step ids', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: 'ryn', task: 'Build', deps: ['ghost'], status: 'done', approval: false, on_fail: 'abort' },
      ],
    })
    const { edges } = buildFlowDag(flow)
    expect(edges).toHaveLength(0)
  })

  it('passes status through to node data', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    const s2 = nodes.find((n) => n.data.stepId === 's2')!
    expect(s2.data.status).toBe('waiting_approval')
  })

  it('passes approval flag through to node data as scalar', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    const s2 = nodes.find((n) => n.data.stepId === 's2')!
    expect(s2.data.approval).toBe(true)
    expect(typeof s2.data.approval).toBe('boolean')
  })

  it('passes on_fail through to node data', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    const s3 = nodes.find((n) => n.data.stepId === 's3')!
    expect(s3.data.onFail).toBe('continue')
  })

  it('all node data fields are scalars (G7 compliance)', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    for (const node of nodes) {
      for (const [, val] of Object.entries(node.data)) {
        expect(typeof val).not.toBe('object')
      }
    }
  })

  it('all nodes have dagre-assigned numeric positions', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    for (const node of nodes) {
      expect(typeof node.position.x).toBe('number')
      expect(typeof node.position.y).toBe('number')
    }
  })

  it('truncates long task label to ≤50 chars + ellipsis', () => {
    const longTask = 'X'.repeat(100)
    const flow = makeFlow({
      steps: [{ id: 's1', soul: 'ryn', task: longTask, deps: [], status: 'pending', approval: false, on_fail: 'abort' }],
    })
    const { nodes } = buildFlowDag(flow)
    expect(nodes[0].data.label.length).toBeLessThanOrEqual(53)
  })

  it('lays out left→right (source.x < target.x for a dep edge)', () => {
    const flow = makeFlow()
    const { nodes } = buildFlowDag(flow)
    const s1 = nodes.find((n) => n.data.stepId === 's1')!
    const s2 = nodes.find((n) => n.data.stepId === 's2')!
    // LR: dependency target sits to the right of its source
    expect(s1.position.x).toBeLessThan(s2.position.x)
  })

  it('animates only edges entering a running step', () => {
    const flow = makeFlow({
      steps: [
        { id: 'a', soul: 'ryn', task: 'A', deps: [], status: 'done', approval: false, on_fail: 'abort' },
        { id: 'b', soul: 'nex', task: 'B', deps: ['a'], status: 'running', approval: false, on_fail: 'abort' },
        { id: 'c', soul: 'ryn', task: 'C', deps: ['b'], status: 'pending', approval: false, on_fail: 'abort' },
      ],
    })
    const { edges } = buildFlowDag(flow)
    const toB = edges.find((e) => e.target === 'fs__b')!
    const toC = edges.find((e) => e.target === 'fs__c')!
    expect(toB.animated).toBe(true)   // a→b: b is running
    expect(toC.animated).toBe(false)  // b→c: c is pending
  })
})

// ── stepsFromGraph ────────────────────────────────────────────────────────────

function makeEditorNode(
  stepId: string,
  overrides: Partial<EditorNodeData> = {},
): GraphNode {
  return {
    id: `fe__${stepId}`,
    type: 'task' as const,
    position: { x: 0, y: 0 },
    data: {
      label: overrides.task ?? 'test task',
      nodeType: 'task' as const,
      stepId,
      soul: 'ryn',
      task: 'test task',
      retry: 1,
      approval: false,
      on_fail: 'abort',
      kind: 'agent' as const,
      ...overrides,
    } as EditorNodeData,
  }
}

describe('stepsFromGraph', () => {
  it('returns empty array for empty nodes', () => {
    expect(stepsFromGraph([], [])).toEqual([])
  })

  it('each node becomes one step with correct id', () => {
    const nodes = [makeEditorNode('s1'), makeEditorNode('s2')]
    const steps = stepsFromGraph(nodes, [])
    expect(steps).toHaveLength(2)
    expect(steps.map((s) => s.id)).toEqual(['s1', 's2'])
  })

  it('deps populated from incoming edges', () => {
    const nodes = [makeEditorNode('s1'), makeEditorNode('s2')]
    const edges: GraphEdge[] = [{ id: 'e1', source: 'fe__s1', target: 'fe__s2' }]
    const steps = stepsFromGraph(nodes, edges)
    const s2 = steps.find((s) => s.id === 's2')!
    expect(s2.deps).toEqual(['s1'])
  })

  it('node with no incoming edges has empty deps', () => {
    const nodes = [makeEditorNode('s1'), makeEditorNode('s2')]
    const edges: GraphEdge[] = [{ id: 'e1', source: 'fe__s1', target: 'fe__s2' }]
    const steps = stepsFromGraph(nodes, edges)
    const s1 = steps.find((s) => s.id === 's1')!
    expect(s1.deps).toEqual([])
  })

  it('preserves soul, task, retry, approval, on_fail from node data', () => {
    const nodes = [
      makeEditorNode('s1', { soul: 'nex', task: 'Review', retry: 2, approval: true, on_fail: 'continue' }),
    ]
    const [step] = stepsFromGraph(nodes, [])
    expect(step.soul).toBe('nex')
    expect(step.task).toBe('Review')
    expect(step.retry).toBe(2)
    expect(step.approval).toBe(true)
    expect(step.on_fail).toBe('continue')
  })

  it('multiple deps (fan-in) all appear in deps array', () => {
    const nodes = [makeEditorNode('a'), makeEditorNode('b'), makeEditorNode('c')]
    const edges: GraphEdge[] = [
      { id: 'e1', source: 'fe__a', target: 'fe__c' },
      { id: 'e2', source: 'fe__b', target: 'fe__c' },
    ]
    const steps = stepsFromGraph(nodes, edges)
    const c = steps.find((s) => s.id === 'c')!
    expect(c.deps.sort()).toEqual(['a', 'b'])
  })

  it('round-trip: editorGraphFromFlow → stepsFromGraph preserves ids', () => {
    const flow = makeFlow()
    const { nodes, edges } = editorGraphFromFlow(flow)
    const steps = stepsFromGraph(nodes, edges)
    const ids = steps.map((s) => s.id).sort()
    expect(ids).toEqual(['s1', 's2', 's3'])
  })

  it('round-trip: deps are preserved after editorGraphFromFlow → stepsFromGraph', () => {
    const flow = makeFlow()
    const { nodes, edges } = editorGraphFromFlow(flow)
    const steps = stepsFromGraph(nodes, edges)
    const s2 = steps.find((s) => s.id === 's2')!
    const s3 = steps.find((s) => s.id === 's3')!
    expect(s2.deps).toEqual(['s1'])
    expect(s3.deps).toEqual(['s2'])
  })
})

// ── editorGraphFromFlow ───────────────────────────────────────────────────────

describe('editorGraphFromFlow', () => {
  it('returns empty graph for flow with no steps', () => {
    const flow = makeFlow({ steps: [] })
    const { nodes, edges } = editorGraphFromFlow(flow)
    expect(nodes).toHaveLength(0)
    expect(edges).toHaveLength(0)
  })

  it('creates one node per step', () => {
    const flow = makeFlow()
    const { nodes } = editorGraphFromFlow(flow)
    expect(nodes).toHaveLength(3)
  })

  it('nodes have stepId in data', () => {
    const flow = makeFlow()
    const { nodes } = editorGraphFromFlow(flow)
    const stepIds = nodes.map((n) => (n.data as EditorNodeData).stepId).sort()
    expect(stepIds).toEqual(['s1', 's2', 's3'])
  })

  it('creates dep edges between editor nodes', () => {
    const flow = makeFlow()
    const { edges } = editorGraphFromFlow(flow)
    expect(edges).toHaveLength(2)
    expect(edges.find((e) => e.source === 'fe__s1' && e.target === 'fe__s2')).toBeDefined()
    expect(edges.find((e) => e.source === 'fe__s2' && e.target === 'fe__s3')).toBeDefined()
  })

  it('all nodes have dagre-assigned numeric positions', () => {
    const flow = makeFlow()
    const { nodes } = editorGraphFromFlow(flow)
    for (const n of nodes) {
      expect(typeof n.position.x).toBe('number')
      expect(typeof n.position.y).toBe('number')
    }
  })

  it('LR layout: s1.x < s2.x < s3.x (sequential deps)', () => {
    const flow = makeFlow()
    const { nodes } = editorGraphFromFlow(flow)
    const s1 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's1')!
    const s2 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's2')!
    const s3 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's3')!
    expect(s1.position.x).toBeLessThan(s2.position.x)
    expect(s2.position.x).toBeLessThan(s3.position.x)
  })

  it('all node data fields are scalars (G7 compliance)', () => {
    const flow = makeFlow()
    const { nodes } = editorGraphFromFlow(flow)
    for (const node of nodes) {
      for (const [, val] of Object.entries(node.data)) {
        if (val !== undefined && val !== null) {
          expect(typeof val).not.toBe('object')
        }
      }
    }
  })

  it('approval and on_fail are preserved from flow steps', () => {
    const flow = makeFlow()
    const { nodes } = editorGraphFromFlow(flow)
    const s2 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's2')!
    expect((s2.data as EditorNodeData).approval).toBe(true)
    expect((s2.data as EditorNodeData).on_fail).toBe('abort')
  })

  it('ignores deps that reference missing step ids', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: 'ryn', task: 'Build', deps: ['ghost'], status: 'done', approval: false, on_fail: 'abort' },
      ],
    })
    const { edges } = editorGraphFromFlow(flow)
    expect(edges).toHaveLength(0)
  })

  it('propagates run_id from flow step into node data.runId', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: 'ryn', task: 'Build', deps: [], status: 'done', approval: false, on_fail: 'abort', run_id: 'run_abc123' },
        { id: 's2', soul: 'nex', task: 'Review', deps: ['s1'], status: 'pending', approval: false, on_fail: 'abort' },
      ],
    })
    const { nodes } = editorGraphFromFlow(flow)
    const s1 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's1')!
    const s2 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's2')!
    expect((s1.data as EditorNodeData).runId).toBe('run_abc123')
    expect((s2.data as EditorNodeData).runId).toBeNull()
  })

  it('runId is a string scalar or null (G7 compliance)', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: 'ryn', task: 'Build', deps: [], status: 'done', approval: false, on_fail: 'abort', run_id: 'run_xyz' },
      ],
    })
    const { nodes } = editorGraphFromFlow(flow)
    const runId = (nodes[0].data as EditorNodeData).runId
    expect(typeof runId === 'string' || runId === null).toBe(true)
  })

  it('step.type=input maps to node data.kind=input', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: '', task: 'hello', deps: [], status: 'pending', approval: false, on_fail: 'abort', type: 'input' },
        { id: 's2', soul: 'ryn', task: 'use it', deps: ['s1'], status: 'pending', approval: false, on_fail: 'abort', type: 'agent' },
      ],
    })
    const { nodes } = editorGraphFromFlow(flow)
    const s1 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's1')!
    const s2 = nodes.find((n) => (n.data as EditorNodeData).stepId === 's2')!
    expect((s1.data as EditorNodeData).kind).toBe('input')
    expect((s2.data as EditorNodeData).kind).toBe('agent')
  })

  it('step.type missing defaults to kind=agent', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: 'ryn', task: 'Build', deps: [], status: 'pending', approval: false, on_fail: 'abort' },
      ],
    })
    const { nodes } = editorGraphFromFlow(flow)
    expect((nodes[0].data as EditorNodeData).kind).toBe('agent')
  })

  it('step.output propagates to node data.output as scalar', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: '', task: 'hi', deps: [], status: 'done', approval: false, on_fail: 'abort', type: 'input', output: 'hello world' },
      ],
    })
    const { nodes } = editorGraphFromFlow(flow)
    expect((nodes[0].data as EditorNodeData).output).toBe('hello world')
  })

  it('step.output null/missing yields null', () => {
    const flow = makeFlow({
      steps: [
        { id: 's1', soul: 'ryn', task: 'Build', deps: [], status: 'pending', approval: false, on_fail: 'abort' },
      ],
    })
    const { nodes } = editorGraphFromFlow(flow)
    expect((nodes[0].data as EditorNodeData).output).toBeNull()
  })
})

// ── stepsFromGraph kind→type serialization ────────────────────────────────────

describe('stepsFromGraph kind→type serialization', () => {
  it('kind=input node serializes to type=input in WriteStep', () => {
    const nodes: GraphNode[] = [
      makeEditorNode('s1', { kind: 'input' as const, soul: '', task: 'val' }),
    ]
    const [step] = stepsFromGraph(nodes, [])
    expect(step.type).toBe('input')
  })

  it('kind=agent node serializes to type=agent in WriteStep', () => {
    const nodes: GraphNode[] = [
      makeEditorNode('s1', { kind: 'agent' as const }),
    ]
    const [step] = stepsFromGraph(nodes, [])
    expect(step.type).toBe('agent')
  })

  it('round-trip: input node kind preserved through editorGraphFromFlow → stepsFromGraph', () => {
    const flow = makeFlow({
      steps: [
        { id: 'in1', soul: '', task: 'start value', deps: [], status: 'pending', approval: false, on_fail: 'abort', type: 'input' },
        { id: 'ag1', soul: 'ryn', task: 'use {{in1}}', deps: ['in1'], status: 'pending', approval: false, on_fail: 'abort', type: 'agent' },
      ],
    })
    const { nodes, edges } = editorGraphFromFlow(flow)
    const steps = stepsFromGraph(nodes, edges)
    const inputStep = steps.find((s) => s.id === 'in1')!
    const agentStep = steps.find((s) => s.id === 'ag1')!
    expect(inputStep.type).toBe('input')
    expect(agentStep.type).toBe('agent')
    expect(agentStep.deps).toEqual(['in1'])
  })
})
