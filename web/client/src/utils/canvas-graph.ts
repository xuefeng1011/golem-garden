/**
 * canvas-graph.ts — Pure graph builder for CanvasView
 * G7: data fields contain only scalars (id, label, numbers) — no large objects
 * G9: dagre layout is pre-computed once at data load time, not on drag/events
 */
import dagre from 'dagre'
import type { RunMeta } from '@/api/hermes/console'
import type { MailboxMessage } from '@/api/hermes/souls'
import type { Mission } from '@/api/hermes/missions'
import type { Flow } from '@/api/hermes/flows'

// ── Types ─────────────────────────────────────────────────────────────────────

export interface GraphNode {
  id: string
  type: 'soul' | 'run' | 'session' | 'mission' | 'task' | 'flowstep'
  position: { x: number; y: number }
  data: GraphNodeData
}

export interface GraphNodeData {
  label: string
  nodeType: 'soul' | 'run' | 'session' | 'mission' | 'task'
  // soul node extras
  runCount?: number
  successRate?: number
  totalCost?: number
  // run node extras
  runId?: string
  soul?: string
  result?: string
  durationMs?: number
  costUsd?: number
  model?: string
  tsStart?: string
  // session node extras
  sessionId?: string
  childCount?: number
  // mission/task extras
  missionId?: string
  status?: string
  taskIdx?: number
  // flowstep extras
  flowId?: string
  stepId?: string
  onFail?: string
  approval?: boolean
  // timeline extras
  timeIndex?: number
  soulIndex?: number
}

export interface GraphEdge {
  id: string
  source: string
  target: string
  label?: string
  animated?: boolean
}

export interface GraphData {
  nodes: GraphNode[]
  edges: GraphEdge[]
}

// ── Layout ────────────────────────────────────────────────────────────────────

// n8n 식 노드 치수 — N8nNode.vue 와 일치(width 210). 여백은 n8n 처럼 넉넉히.
const NODE_W = 210
const NODE_H = 66

export function layoutWithDagre(
  nodes: GraphNode[],
  edges: GraphEdge[],
  direction: 'TB' | 'LR' = 'LR',
): GraphNode[] {
  if (nodes.length === 0) return nodes

  const g = new dagre.graphlib.Graph()
  g.setDefaultEdgeLabel(() => ({}))
  g.setGraph({ rankdir: direction, nodesep: 44, ranksep: 130, marginx: 24, marginy: 24 })

  for (const node of nodes) {
    g.setNode(node.id, { width: NODE_W, height: NODE_H })
  }

  for (const edge of edges) {
    if (g.hasNode(edge.source) && g.hasNode(edge.target)) {
      g.setEdge(edge.source, edge.target)
    }
  }

  dagre.layout(g)

  return nodes.map((node) => {
    const pos = g.node(node.id)
    return {
      ...node,
      position: {
        x: pos ? pos.x - NODE_W / 2 : node.position.x,
        y: pos ? pos.y - NODE_H / 2 : node.position.y,
      },
    }
  })
}

// ── Execution Flow ────────────────────────────────────────────────────────────

const MAX_RUNS_PER_SOUL = 10

/**
 * Build execution flow graph:
 * - SOUL nodes with aggregated stats (run count, success rate, cost)
 * - Recent run child nodes (max MAX_RUNS_PER_SOUL per soul, collapsed by default)
 * - Mailbox edges from→to with message count label
 */
export function buildExecutionFlow(
  runs: RunMeta[],
  mailboxEntries: MailboxMessage[],
): GraphData {
  // Group runs by soul
  const bySoul = new Map<string, RunMeta[]>()
  for (const run of runs) {
    const soul = run.soul || 'unknown'
    const list = bySoul.get(soul) ?? []
    list.push(run)
    bySoul.set(soul, list)
  }

  const nodes: GraphNode[] = []
  const edges: GraphEdge[] = []

  // Soul nodes
  for (const [soul, soulRuns] of bySoul) {
    const successCount = soulRuns.filter((r) => r.result === 'success').length
    const successRate = soulRuns.length > 0 ? successCount / soulRuns.length : 0
    const totalCost = soulRuns.reduce((acc, r) => acc + (r.cost_usd ?? 0), 0)

    nodes.push({
      id: `soul__${soul}`,
      type: 'soul',
      position: { x: 0, y: 0 },
      data: {
        label: soul,
        nodeType: 'soul',
        runCount: soulRuns.length,
        successRate: Math.round(successRate * 100),
        totalCost,
        soul,
      },
    })

    // Recent run child nodes (max MAX_RUNS_PER_SOUL, sorted newest first)
    const sorted = [...soulRuns].sort(
      (a, b) => new Date(b.ts_start).getTime() - new Date(a.ts_start).getTime(),
    )
    const recentRuns = sorted.slice(0, MAX_RUNS_PER_SOUL)

    for (const run of recentRuns) {
      const runNodeId = `run__${run.run_id}`
      nodes.push({
        id: runNodeId,
        type: 'run',
        position: { x: 0, y: 0 },
        data: {
          // 라벨 다이어트: 결과는 상태 점으로 표시 (n8n식) — 제목은 run id 만
          label: run.run_id.slice(0, 8),
          nodeType: 'run',
          runId: run.run_id,
          soul: run.soul,
          result: run.result,
          durationMs: run.duration_ms,
          costUsd: run.cost_usd,
          model: run.model,
          tsStart: run.ts_start,
        },
      })
      edges.push({
        id: `e__soul__${soul}__${run.run_id}`,
        source: `soul__${soul}`,
        target: runNodeId,
      })
    }
  }

  // Mailbox edges: aggregate by from→to pair
  const mailEdgeCounts = new Map<string, number>()
  for (const msg of mailboxEntries) {
    if (!msg.from || !msg.to) continue
    const key = `${msg.from}|${msg.to}`
    mailEdgeCounts.set(key, (mailEdgeCounts.get(key) ?? 0) + 1)
  }

  for (const [key, count] of mailEdgeCounts) {
    const [from, to] = key.split('|')
    const srcId = `soul__${from}`
    const tgtId = `soul__${to}`
    const srcExists = nodes.some((n) => n.id === srcId)
    const tgtExists = nodes.some((n) => n.id === tgtId)
    if (srcExists && tgtExists) {
      edges.push({
        id: `mail__${key}`,
        source: srcId,
        target: tgtId,
        label: `${count}`,
      })
    }
  }

  const laidOut = layoutWithDagre(nodes, edges, 'LR')
  return { nodes: laidOut, edges }
}

// ── Mission DAG ───────────────────────────────────────────────────────────────

/**
 * Build a DAG for a single mission: mission node → task nodes in idx order
 */
export function buildMissionDag(mission: Mission): GraphData {
  const nodes: GraphNode[] = []
  const edges: GraphEdge[] = []

  // Mission root node
  const missionNodeId = `mission__${mission.id}`
  nodes.push({
    id: missionNodeId,
    type: 'mission',
    position: { x: 0, y: 0 },
    data: {
      label: mission.goal.length > 60 ? mission.goal.slice(0, 57) + '…' : mission.goal,
      nodeType: 'mission',
      missionId: mission.id,
      status: mission.status,
    },
  })

  // Sort tasks by idx
  const tasks = [...mission.tasks].sort((a, b) => a.idx - b.idx)

  let prevNodeId = missionNodeId
  for (const task of tasks) {
    const taskNodeId = `task__${mission.id}__${task.idx}`
    nodes.push({
      id: taskNodeId,
      type: 'task',
      position: { x: 0, y: 0 },
      data: {
        label: task.task.length > 50 ? task.task.slice(0, 47) + '…' : task.task,
        nodeType: 'task',
        missionId: mission.id,
        taskIdx: task.idx,
        soul: task.soul,
        status: task.status,
      },
    })
    edges.push({
      id: `e__task__${mission.id}__${task.idx}`,
      source: prevNodeId,
      target: taskNodeId,
      animated: task.status === 'in_progress',
    })
    prevNodeId = taskNodeId
  }

  const laidOut = layoutWithDagre(nodes, edges, 'LR')
  return { nodes: laidOut, edges }
}

// ── Session Tree ──────────────────────────────────────────────────────────────

/**
 * Build a session tree graph:
 * - Session nodes (grouped by session_id)
 * - Run child nodes under each session
 */
export function buildSessionTree(runs: RunMeta[]): GraphData {
  const nodes: GraphNode[] = []
  const edges: GraphEdge[] = []

  const bySession = new Map<string, RunMeta[]>()
  for (const run of runs) {
    const sid = run.session_id || 'no-session'
    const list = bySession.get(sid) ?? []
    list.push(run)
    bySession.set(sid, list)
  }

  for (const [sid, sessionRuns] of bySession) {
    const sessionNodeId = `session__${sid}`
    nodes.push({
      id: sessionNodeId,
      type: 'session',
      position: { x: 0, y: 0 },
      data: {
        label: `Session ${sid.slice(0, 8)}`,
        nodeType: 'session',
        sessionId: sid,
        childCount: sessionRuns.length,
      },
    })

    for (const run of sessionRuns) {
      const runNodeId = `run__${run.run_id}`
      nodes.push({
        id: runNodeId,
        type: 'run',
        position: { x: 0, y: 0 },
        data: {
          // 제목은 soul, 결과는 상태 점으로 (n8n식)
          label: run.soul || 'host',
          nodeType: 'run',
          runId: run.run_id,
          soul: run.soul,
          result: run.result,
          durationMs: run.duration_ms,
          costUsd: run.cost_usd,
          model: run.model,
          tsStart: run.ts_start,
        },
      })
      edges.push({
        id: `e__session__${sid}__${run.run_id}`,
        source: sessionNodeId,
        target: runNodeId,
      })
    }
  }

  const laidOut = layoutWithDagre(nodes, edges, 'LR')
  return { nodes: laidOut, edges }
}

// ── Timeline Duration Filter ──────────────────────────────────────────────────

export type TimelineRange = '24h' | '7d' | 'all'

export function filterRunsByRange(runs: RunMeta[], range: TimelineRange): RunMeta[] {
  if (range === 'all') return runs
  const now = Date.now()
  const cutoff = range === '24h' ? now - 24 * 60 * 60 * 1000 : now - 7 * 24 * 60 * 60 * 1000
  return runs.filter((r) => new Date(r.ts_start).getTime() >= cutoff)
}

// ── Timeline (Swimlane) ───────────────────────────────────────────────────────

const X_STEP = 220  // horizontal gap between time-slots (G9: fixed, no recompute)
const Y_STEP = 100  // vertical gap between soul rows

/**
 * Build a swimlane timeline graph (G9: positions computed once, never on drag).
 * - Rows: one per unique soul (sorted by first appearance)
 * - Columns: runs sorted by ts_start ascending
 * - Edges: consecutive runs in the same session_id are connected
 */
export function buildTimeline(runs: RunMeta[], range: TimelineRange = 'all'): GraphData {
  const filtered = filterRunsByRange(runs, range)
  if (filtered.length === 0) return { nodes: [], edges: [] }

  // Sort runs by ts_start ascending (run_id 타이브레이커 — 동시각 런의 결정론적 배치)
  const sorted = [...filtered].sort(
    (a, b) =>
      new Date(a.ts_start).getTime() - new Date(b.ts_start).getTime() ||
      a.run_id.localeCompare(b.run_id),
  )

  // Build soul index (insertion order = first-appearance order)
  const soulOrder: string[] = []
  const soulIndexMap = new Map<string, number>()
  for (const run of sorted) {
    const soul = run.soul || 'unknown'
    if (!soulIndexMap.has(soul)) {
      soulIndexMap.set(soul, soulOrder.length)
      soulOrder.push(soul)
    }
  }

  const nodes: GraphNode[] = []
  const edges: GraphEdge[] = []

  // Track last run per session for edge building
  const lastRunInSession = new Map<string, string>()

  for (let i = 0; i < sorted.length; i++) {
    const run = sorted[i]
    const soul = run.soul || 'unknown'
    const soulIdx = soulIndexMap.get(soul) ?? 0
    const sid = run.session_id || ''
    const runNodeId = `tl__${run.run_id}`

    const durSec = run.duration_ms != null ? (run.duration_ms / 1000).toFixed(1) + 's' : '—'

    nodes.push({
      id: runNodeId,
      type: 'run',
      // G9: position computed once here — x = time-slot index, y = soul lane
      position: { x: i * X_STEP, y: soulIdx * Y_STEP },
      data: {
        // 결과는 상태 점으로 — 제목은 soul · 소요시간
        label: `${soul} · ${durSec}`,
        nodeType: 'run',
        runId: run.run_id,
        soul,
        result: run.result,
        durationMs: run.duration_ms,
        costUsd: run.cost_usd,
        model: run.model,
        tsStart: run.ts_start,
        timeIndex: i,
        soulIndex: soulIdx,
      },
    })

    // Connect to previous run in the same session (workflow narrative edge)
    if (sid) {
      const prevId = lastRunInSession.get(sid)
      if (prevId) {
        edges.push({
          id: `tl_sess__${sid}__${run.run_id}`,
          source: prevId,
          target: runNodeId,
        })
      }
      lastRunInSession.set(sid, runNodeId)
    }
  }

  return { nodes, edges }
}

// ── Flow DAG ──────────────────────────────────────────────────────────────────

/**
 * Build a DAG for a single Flow (from Flow Engine):
 * - Each step becomes a node
 * - deps[] become edges (source dep → target step)
 * - Uses dagre TB layout (same as buildMissionDag)
 */
export function buildFlowDag(flow: Flow): GraphData {
  if (flow.steps.length === 0) return { nodes: [], edges: [] }

  const nodes: GraphNode[] = []
  const edges: GraphEdge[] = []

  const stepIds = new Set(flow.steps.map((s) => s.id))

  for (const step of flow.steps) {
    nodes.push({
      id: `fs__${step.id}`,
      type: 'flowstep',
      position: { x: 0, y: 0 },
      data: {
        label: step.task.length > 50 ? step.task.slice(0, 47) + '…' : step.task,
        nodeType: 'task',
        soul: step.soul,
        status: step.status,
        stepId: step.id,
        flowId: flow.flow_id,
        onFail: step.on_fail,
        approval: step.approval,
      },
    })

    for (const dep of step.deps) {
      if (stepIds.has(dep)) {
        edges.push({
          id: `fe__${dep}__${step.id}`,
          source: `fs__${dep}`,
          target: `fs__${step.id}`,
          // 실행 중인 step 으로 들어가는 엣지는 애니메이션 (n8n 실행 표시)
          animated: step.status === 'running',
        })
      }
    }
  }

  const laidOut = layoutWithDagre(nodes, edges, 'LR')
  return { nodes: laidOut, edges }
}
