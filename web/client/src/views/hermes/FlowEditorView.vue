<script setup lang="ts">
/**
 * FlowEditorView — n8n-style visual workflow editor for Flow Engine flows.
 * G7: nodes/edges shallowRef; node.data scalars only.
 * G8: N8nNode plain div.
 * G9: layout only on load or [자동 정렬] button; never on drag/connect.
 */
import { shallowRef, ref, computed, watch, markRaw, onUnmounted } from 'vue'
import {
  VueFlow,
  useVueFlow,
  MarkerType,
  type NodeMouseEvent,
  type Connection,
  type NodeTypesObject,
  type Node,
} from '@vue-flow/core'
import { Background, BackgroundVariant } from '@vue-flow/background'
import { Controls } from '@vue-flow/controls'
import { useI18n } from 'vue-i18n'
import { useDialog, useMessage, NIcon, NSpin } from 'naive-ui'
import { onBeforeRouteLeave } from 'vue-router'
import { FolderOpenOutline, AlertCircleOutline, GitNetworkOutline } from '@vicons/ionicons5'
import '@vue-flow/core/dist/style.css'
import '@vue-flow/core/dist/theme-default.css'

import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchSouls } from '@/api/hermes/souls'
import { fetchFlows, createFlow, updateFlow } from '@/api/hermes/flows'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import type { Soul } from '@/api/hermes/souls'
import type { GraphNode, GraphEdge, EditorNodeData } from '@/utils/canvas-graph'
import {
  layoutWithDagre,
  stepsFromGraph,
} from '@/utils/canvas-graph'

import N8nNode from '@/components/hermes/canvas/N8nNode.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import EditorToolbar from '@/components/hermes/flow-editor/EditorToolbar.vue'
import StepFormPanel from '@/components/hermes/flow-editor/StepFormPanel.vue'
import RunPanel from '@/components/hermes/flow-editor/RunPanel.vue'

const { t } = useI18n()
const profilesStore = useProfilesStore()
const dialog = useDialog()
const message = useMessage()

// ── Vue Flow instance ─────────────────────────────────────────────────────────
const { fitView, getSelectedNodes, getSelectedEdges } = useVueFlow()

// ── Node type registry (G8) ───────────────────────────────────────────────────
const nodeTypes: NodeTypesObject = markRaw({ task: N8nNode as NodeTypesObject[string] })

const defaultEdgeOptions = markRaw({
  type: 'default',
  markerEnd: MarkerType.ArrowClosed,
})

// ── Graph state (G7: shallowRef) ──────────────────────────────────────────────
const nodes = shallowRef<GraphNode[]>([])
const edges = shallowRef<GraphEdge[]>([])

// ── Editor state ──────────────────────────────────────────────────────────────
const goal = ref('')
const flowId = ref<string | null>(null)
const dirty = ref(false)
const saving = ref(false)
const loading = ref(false)
const loadError = ref<string | null>(null)

// Step counter for unique IDs
let stepCounter = 0

// ── Selected node (for form panel) ───────────────────────────────────────────
const selectedNodeId = ref<string | null>(null)
const selectedNodeData = computed<EditorNodeData | null>(() => {
  if (!selectedNodeId.value) return null
  const found = nodes.value.find((n) => n.id === selectedNodeId.value)
  return found ? (found.data as EditorNodeData) : null
})

// ── Souls list ────────────────────────────────────────────────────────────────
const souls = ref<Soul[]>([])

// ── Run panel ─────────────────────────────────────────────────────────────────
const running = ref(false)
const runLines = ref<string[]>([])
let sseAbort: (() => void) | null = null

// Waiting approval steps derived from current nodes
const waitingSteps = computed(() =>
  nodes.value
    .filter((n) => (n.data as EditorNodeData).status === 'waiting_approval')
    .map((n) => ({
      stepId: (n.data as EditorNodeData).stepId,
      label: (n.data as EditorNodeData).label,
    })),
)

// ── All step options (for goto selector in form panel) ───────────────────────
const allStepOptions = computed(() =>
  nodes.value.map((n) => {
    const d = n.data as EditorNodeData
    return { label: d.label || d.stepId, value: d.stepId }
  }),
)

// ── Dirty tracking ────────────────────────────────────────────────────────────
watch([nodes, edges, goal], () => { dirty.value = true }, { flush: 'sync' })

// ── Load ──────────────────────────────────────────────────────────────────────
async function loadData() {
  const pid = profilesStore.activeProfile?.id
  if (!pid) return

  loading.value = true
  loadError.value = null

  try {
    const [fetchedSouls] = await Promise.all([
      fetchSouls(pid).catch(() => [] as Soul[]),
    ])
    souls.value = fetchedSouls
    dirty.value = false
  } catch (err) {
    loadError.value = err instanceof Error ? err.message : String(err)
  } finally {
    loading.value = false
  }
}

watch(
  () => profilesStore.activeProfile?.id,
  (id) => { if (id) loadData() },
  { immediate: true },
)

// ── Templates ─────────────────────────────────────────────────────────────────
function applyTemplate(kind: 'serial' | 'parallel') {
  const firstSoul = souls.value[0]?.id ?? ''

  if (kind === 'serial') {
    goal.value = t('flowEditor.templateSerialGoal')
    const rawNodes: GraphNode[] = [
      makeNode('step_1', t('flowEditor.templateDesign'), firstSoul),
      makeNode('step_2', t('flowEditor.templateImpl'), firstSoul),
      makeNode('step_3', t('flowEditor.templateVerify'), firstSoul),
    ]
    const rawEdges: GraphEdge[] = [
      { id: 'te1', source: rawNodes[0].id, target: rawNodes[1].id },
      { id: 'te2', source: rawNodes[1].id, target: rawNodes[2].id },
    ]
    nodes.value = layoutWithDagre(rawNodes, rawEdges, 'LR')
    edges.value = rawEdges
  } else {
    goal.value = t('flowEditor.templateParallelGoal')
    const rawNodes: GraphNode[] = [
      makeNode('step_1', t('flowEditor.templateImpl'), firstSoul),
      makeNode('step_2', t('flowEditor.templateImpl2'), firstSoul),
      makeNode('step_3', t('flowEditor.templateVerify'), firstSoul),
    ]
    const rawEdges: GraphEdge[] = [
      { id: 'te1', source: rawNodes[0].id, target: rawNodes[2].id },
      { id: 'te2', source: rawNodes[1].id, target: rawNodes[2].id },
    ]
    nodes.value = layoutWithDagre(rawNodes, rawEdges, 'LR')
    edges.value = rawEdges
  }
  dirty.value = true
  setTimeout(() => fitView({ padding: 0.15 }), 50)
}

// ── Node factory ──────────────────────────────────────────────────────────────
function makeNode(stepId: string, task = '', soul = ''): GraphNode {
  return {
    id: `fe__${stepId}`,
    type: 'task',
    position: { x: 0, y: 0 },
    data: {
      label: task.length > 40 ? task.slice(0, 37) + '…' : (task || stepId),
      nodeType: 'task',
      stepId,
      soul,
      task,
      retry: 1,
      approval: false,
      on_fail: 'abort',
      status: 'pending',
    } as EditorNodeData,
  }
}

// ── Add step ──────────────────────────────────────────────────────────────────
function addStep() {
  stepCounter += 1
  const stepId = `step_${Date.now()}_${stepCounter}`
  const firstSoul = souls.value[0]?.id ?? ''
  const selected = getSelectedNodes.value
  const lastSelected = selected.length > 0 ? selected[selected.length - 1] : null

  // Position: right of last selected node, or stacked below last node
  const base = lastSelected?.position ?? (
    nodes.value.length > 0
      ? nodes.value[nodes.value.length - 1].position
      : { x: 100, y: 100 }
  )

  const newNode = makeNode(stepId, '', firstSoul)
  newNode.position = { x: base.x + 260, y: base.y }

  const newEdges = [...edges.value]
  if (lastSelected) {
    newEdges.push({
      id: `e_auto_${stepId}`,
      source: lastSelected.id,
      target: newNode.id,
    })
  }

  // G7: replace shallowRef
  nodes.value = [...nodes.value, newNode]
  edges.value = newEdges
  selectedNodeId.value = newNode.id
}

// ── Auto layout (G9: only here, not on drag) ──────────────────────────────────
function autoLayout() {
  nodes.value = layoutWithDagre([...nodes.value], [...edges.value], 'LR')
  setTimeout(() => fitView({ padding: 0.15 }), 50)
}

// ── Validate ─────────────────────────────────────────────────────────────────
function validate(): boolean {
  const errorIds: string[] = []
  for (const node of nodes.value) {
    const d = node.data as EditorNodeData
    if (!d.task || d.task.trim() === '') {
      errorIds.push(node.id)
    }
  }

  if (errorIds.length > 0) {
    // Mark error nodes (G7: replace shallowRef)
    nodes.value = nodes.value.map((n) => ({
      ...n,
      data: { ...n.data, hasError: errorIds.includes(n.id) } as EditorNodeData,
    }))
    message.warning(t('flowEditor.validateErrors', { n: errorIds.length }))
    return false
  }

  // Clear errors
  nodes.value = nodes.value.map((n) => ({
    ...n,
    data: { ...n.data, hasError: false } as EditorNodeData,
  }))
  message.success(t('flowEditor.validateOk'))
  return true
}

// ── Save ──────────────────────────────────────────────────────────────────────
async function save() {
  const pid = profilesStore.activeProfile?.id
  if (!pid) return

  saving.value = true
  try {
    const steps = stepsFromGraph(nodes.value, edges.value)
    const payload = { goal: goal.value || t('flowEditor.defaultGoal'), steps }

    if (flowId.value) {
      await updateFlow(pid, flowId.value, payload)
    } else {
      const res = await createFlow(pid, payload)
      flowId.value = res.flow_id
    }

    dirty.value = false
    message.success(t('flowEditor.saveSuccess'))
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err)
    message.error(`${t('flowEditor.saveFailed')}: ${msg}`)
    // Highlight nodes mentioned in error detail (best-effort)
    const detail = msg.toLowerCase()
    nodes.value = nodes.value.map((n) => ({
      ...n,
      data: {
        ...n.data,
        hasError: detail.includes((n.data as EditorNodeData).stepId),
      } as EditorNodeData,
    }))
  } finally {
    saving.value = false
  }
}

// ── Run ───────────────────────────────────────────────────────────────────────
async function run() {
  const pid = profilesStore.activeProfile?.id
  if (!pid || !flowId.value) return

  if (dirty.value) {
    await save()
    if (dirty.value) return // save failed
  }

  running.value = true
  runLines.value = []

  try {
    const { run_id } = await startForge(pid, 'flow', ['run', flowId.value])

    sseAbort = streamForgeEvents(
      run_id,
      (evt) => {
        if (evt.line) runLines.value = [...runLines.value, evt.line]
      },
      () => {
        running.value = false
        sseAbort = null
        refreshFlowStatus()
      },
      (err) => {
        running.value = false
        sseAbort = null
        message.error(err.message)
      },
    ).abort

  } catch (err) {
    running.value = false
    message.error(err instanceof Error ? err.message : String(err))
  }
}

async function refreshFlowStatus() {
  const pid = profilesStore.activeProfile?.id
  if (!pid || !flowId.value) return

  try {
    const flows = await fetchFlows(pid)
    const flow = flows.find((f) => f.flow_id === flowId.value)
    if (!flow) return

    // Update node statuses without re-running dagre (G9: preserve positions)
    const statusMap = new Map(flow.steps.map((s) => [s.id, s.status]))
    nodes.value = nodes.value.map((n) => {
      const d = n.data as EditorNodeData
      const newStatus = statusMap.get(d.stepId)
      if (newStatus === undefined) return n
      return { ...n, data: { ...d, status: newStatus } as EditorNodeData }
    })
  } catch {
    // ignore refresh errors silently
  }
}

// ── Approve / Reject ──────────────────────────────────────────────────────────
async function approve(stepId: string) {
  const pid = profilesStore.activeProfile?.id
  if (!pid || !flowId.value) return
  try {
    await startForge(pid, 'flow', ['approve', flowId.value, stepId])
    message.success(t('flowEditor.approved'))
    refreshFlowStatus()
  } catch (err) {
    message.error(err instanceof Error ? err.message : String(err))
  }
}

async function reject(stepId: string) {
  const pid = profilesStore.activeProfile?.id
  if (!pid || !flowId.value) return
  try {
    await startForge(pid, 'flow', ['reject', flowId.value, stepId])
    message.info(t('flowEditor.rejected'))
    refreshFlowStatus()
  } catch (err) {
    message.error(err instanceof Error ? err.message : String(err))
  }
}

// ── Delete selected ───────────────────────────────────────────────────────────
function deleteSelected() {
  const selNodes = getSelectedNodes.value.map((n) => n.id)
  const selEdges = getSelectedEdges.value.map((e) => e.id)
  if (selNodes.length === 0 && selEdges.length === 0) return

  nodes.value = nodes.value.filter((n) => !selNodes.includes(n.id))
  edges.value = edges.value.filter(
    (e) => !selEdges.includes(e.id) && !selNodes.includes(e.source) && !selNodes.includes(e.target),
  )
  if (selectedNodeId.value && selNodes.includes(selectedNodeId.value)) {
    selectedNodeId.value = null
  }
}

// ── Connect handler (G9: no re-layout on connect) ────────────────────────────
function onConnect(conn: Connection) {
  if (!conn.source || !conn.target) return
  // Prevent self-connection
  if (conn.source === conn.target) return

  const edgeId = `e_${conn.source}_${conn.target}`
  // Prevent duplicate
  if (edges.value.some((e) => e.id === edgeId)) return

  edges.value = [
    ...edges.value,
    { id: edgeId, source: conn.source, target: conn.target },
  ]
}

// ── Node drag (G9: only update position, no dagre recompute) ─────────────────
function onNodeDragStop(event: { node: Node }) {
  const draggedNode = event.node
  nodes.value = nodes.value.map((n) =>
    n.id === draggedNode.id
      ? { ...n, position: { ...draggedNode.position } }
      : n,
  )
}

// ── Node click ────────────────────────────────────────────────────────────────
function onNodeClick({ node }: NodeMouseEvent) {
  selectedNodeId.value = node.id
}

function onPaneClick() {
  selectedNodeId.value = null
}

// ── Form update (G7: replace shallowRef with new node objects) ────────────────
function onStepUpdate(patch: Partial<EditorNodeData>) {
  if (!selectedNodeId.value) return
  nodes.value = nodes.value.map((n) => {
    if (n.id !== selectedNodeId.value) return n
    return { ...n, data: { ...n.data, ...patch } as EditorNodeData }
  })
}

// ── Keyboard shortcut: Delete ─────────────────────────────────────────────────
function onKeyDown(e: KeyboardEvent) {
  if (e.key === 'Delete' || e.key === 'Backspace') {
    const active = document.activeElement
    const isInput = active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement
    if (!isInput) deleteSelected()
  }
}

window.addEventListener('keydown', onKeyDown)
onUnmounted(() => {
  window.removeEventListener('keydown', onKeyDown)
  sseAbort?.()
})

// ── Route leave guard ─────────────────────────────────────────────────────────
onBeforeRouteLeave((_to, _from, next) => {
  if (!dirty.value) { next(); return }
  dialog.warning({
    title: t('flowEditor.leaveTitle'),
    content: t('flowEditor.leaveContent'),
    positiveText: t('flowEditor.leaveConfirm'),
    negativeText: t('common.cancel'),
    onPositiveClick: () => next(),
    onNegativeClick: () => next(false),
  })
})

// ── Load existing flow (if query param provided) ──────────────────────────────
// For now the editor starts blank; CanvasView links here without a flow id.
// Future: support ?flowId=xxx to load an existing flow.
</script>

<template>
  <div class="flow-editor-view" @keydown.delete.stop>

    <!-- No project -->
    <EmptyState
      v-if="!profilesStore.activeProfile"
      :title="t('flowEditor.noProject')"
      :description="t('flowEditor.noProjectDesc')"
    >
      <template #icon>
        <NIcon><FolderOpenOutline /></NIcon>
      </template>
    </EmptyState>

    <!-- Loading -->
    <div v-else-if="loading" class="center-state">
      <NSpin size="medium" />
      <span class="center-label">{{ t('common.loading') }}</span>
    </div>

    <!-- Error -->
    <div v-else-if="loadError" class="center-state">
      <NIcon size="24" color="var(--error)"><AlertCircleOutline /></NIcon>
      <span class="center-label">{{ loadError }}</span>
    </div>

    <!-- Editor -->
    <template v-else>
      <!-- Toolbar -->
      <EditorToolbar
        v-model:goal="goal"
        :dirty="dirty"
        :saving="saving"
        :has-flow-id="!!flowId"
        :running="running"
        @add-step="addStep"
        @auto-layout="autoLayout"
        @validate="validate"
        @save="save"
        @run="run"
      />

      <!-- Canvas + form panel -->
      <div class="editor-body">

        <!-- Empty canvas guide -->
        <div v-if="nodes.length === 0" class="canvas-empty">
          <div class="empty-icon">
            <NIcon size="48" color="var(--text-muted)"><GitNetworkOutline /></NIcon>
          </div>
          <p class="empty-title">{{ t('flowEditor.emptyTitle') }}</p>
          <p class="empty-desc">{{ t('flowEditor.emptyDesc') }}</p>
          <div class="template-btns">
            <button class="tmpl-btn" @click="applyTemplate('serial')">
              {{ t('flowEditor.templateSerial') }}
            </button>
            <button class="tmpl-btn" @click="applyTemplate('parallel')">
              {{ t('flowEditor.templateParallel') }}
            </button>
          </div>
        </div>

        <!-- Vue Flow canvas (always mounted to keep handle refs alive) -->
        <VueFlow
          v-show="nodes.length > 0"
          :nodes="nodes"
          :edges="edges"
          :node-types="nodeTypes"
          :default-edge-options="defaultEdgeOptions"
          :nodes-draggable="true"
          :nodes-connectable="true"
          fit-view-on-init
          class="editor-flow"
          @connect="onConnect"
          @node-click="onNodeClick"
          @node-drag-stop="onNodeDragStop"
          @pane-click="onPaneClick"
        >
          <Background :variant="BackgroundVariant.Dots" :gap="22" :size="1.4" />
          <Controls />
        </VueFlow>

        <!-- Step form panel (right side) -->
        <StepFormPanel
          v-if="selectedNodeData"
          :data="selectedNodeData"
          :souls="souls"
          :all-step-options="allStepOptions"
          @update="onStepUpdate"
          @close="selectedNodeId = null"
        />
      </div>

      <!-- Run panel (bottom) -->
      <RunPanel
        :lines="runLines"
        :running="running"
        :waiting-steps="waitingSteps"
        @approve="approve"
        @reject="reject"
      />
    </template>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.flow-editor-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.editor-body {
  flex: 1;
  min-height: 0;
  position: relative;
  display: flex;
}

.editor-flow {
  flex: 1;
  width: 100%;
  height: 100%;
  background: $bg-secondary;

  :deep(.vue-flow__edge-path) {
    stroke: var(--border-color, #d0d5dd);
    stroke-width: 1.6;
  }

  :deep(.vue-flow__edge.selected .vue-flow__edge-path),
  :deep(.vue-flow__edge:hover .vue-flow__edge-path) {
    stroke: $accent-primary;
  }

  :deep(.vue-flow__arrowhead) {
    fill: var(--border-color, #d0d5dd);
  }
}

.canvas-empty {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  z-index: 5;
  pointer-events: none;
}

.empty-icon {
  opacity: 0.4;
}

.empty-title {
  font-size: 18px;
  font-weight: 600;
  color: $text-primary;
  margin: 0;
}

.empty-desc {
  font-size: 14px;
  color: $text-muted;
  margin: 0;
  text-align: center;
  max-width: 320px;
}

.template-btns {
  display: flex;
  gap: 10px;
  pointer-events: all;
}

.tmpl-btn {
  padding: 8px 18px;
  background: rgba(var(--accent-primary-rgb), 0.1);
  border: 1px solid rgba(var(--accent-primary-rgb), 0.3);
  border-radius: $radius-sm;
  color: $accent-primary;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: background $transition-fast, border-color $transition-fast;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.18);
    border-color: $accent-primary;
  }
}

.center-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
}

.center-label {
  color: $text-muted;
  font-size: 13px;
}
</style>
