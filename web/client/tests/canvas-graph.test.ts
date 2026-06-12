import { describe, it, expect } from 'vitest'
import {
  buildExecutionFlow,
  buildMissionDag,
  buildSessionTree,
  layoutWithDagre,
} from '@/utils/canvas-graph'
import type { RunMeta } from '@/api/hermes/console'
import type { MailboxMessage } from '@/api/hermes/souls'
import type { Mission } from '@/api/hermes/missions'

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
