<script setup lang="ts">
/**
 * CanvasView — Vue Flow based Canvas (Phase C)
 * G7: nodes/edges are shallowRef; node data contains scalars only
 * G8: custom nodes are plain divs; onlyRenderVisibleElements when >300 nodes
 * G9: dagre layout pre-computed once at load; no recompute on drag/events
 *     vue-flow is in a separate chunk (manualChunks in vite.config.ts)
 */
import { shallowRef, ref, computed, watch, markRaw } from 'vue'
import { VueFlow, useVueFlow, type NodeMouseEvent, type NodeTypesObject } from '@vue-flow/core'
import { Background } from '@vue-flow/background'
import { Controls } from '@vue-flow/controls'
import { useI18n } from 'vue-i18n'
import { NSpin, NIcon, NSelect } from 'naive-ui'
import { AlertCircleOutline, RefreshOutline, FolderOpenOutline } from '@vicons/ionicons5'
import '@vue-flow/core/dist/style.css'
import '@vue-flow/core/dist/theme-default.css'

import { useProfilesStore } from '@/stores/hermes/profiles'
import { useConsoleStore } from '@/stores/hermes/console'
import { fetchRuns } from '@/api/hermes/traces'
import { fetchMailbox } from '@/api/hermes/souls'
import { fetchMissions } from '@/api/hermes/missions'
import { fetchFlows } from '@/api/hermes/flows'
import {
  buildExecutionFlow,
  buildMissionDag,
  buildSessionTree,
  buildTimeline,
  buildFlowDag,
} from '@/utils/canvas-graph'
import type { GraphNodeData, TimelineRange } from '@/utils/canvas-graph'
import type { Mission } from '@/api/hermes/missions'
import type { Flow } from '@/api/hermes/flows'
import type { RunMeta } from '@/api/hermes/console'

import SoulNode from '@/components/hermes/canvas/SoulNode.vue'
import RunNode from '@/components/hermes/canvas/RunNode.vue'
import GenericNode from '@/components/hermes/canvas/GenericNode.vue'
import NodeInfoPanel from '@/components/hermes/canvas/NodeInfoPanel.vue'
import RunDetailDrawer from '@/components/hermes/console/RunDetailDrawer.vue'
import EmptyState from '@/components/common/EmptyState.vue'

const { t } = useI18n()
const profilesStore = useProfilesStore()
const consoleStore = useConsoleStore()

// ── View state ────────────────────────────────────────────────────────────────

type ViewMode = 'timeline' | 'flowdag' | 'flow' | 'mission' | 'session'
const viewMode = ref<ViewMode>('timeline')

// ── Timeline range filter ─────────────────────────────────────────────────────
const timelineRange = ref<TimelineRange>('7d')

// ── Graph data (G7: shallowRef) ───────────────────────────────────────────────
const nodes = shallowRef<ReturnType<typeof buildExecutionFlow>['nodes']>([])
const edges = shallowRef<ReturnType<typeof buildExecutionFlow>['edges']>([])

// ── Data fetching state ───────────────────────────────────────────────────────
const loading = ref(false)
const loadError = ref<string | null>(null)
const runs = ref<RunMeta[]>([])
const missions = ref<Mission[]>([])
const flows = ref<Flow[]>([])
const selectedMissionId = ref<string | null>(null)
const selectedFlowId = ref<string | null>(null)

// ── Node click / info panel ───────────────────────────────────────────────────
const selectedNodeData = ref<GraphNodeData | null>(null)

// ── Run detail drawer (reusing ConsoleView pattern) ───────────────────────────
const drawerVisible = ref(false)

// ── Vue Flow instance ─────────────────────────────────────────────────────────
const { fitView } = useVueFlow()

// G8: onlyRenderVisibleElements when nodes exceed 300
const useVisibleOnly = computed(() => nodes.value.length > 300)

// ── Node type registry (markRaw: skip reactivity on component definitions) ───
const nodeTypes: NodeTypesObject = markRaw({
  soul: SoulNode as NodeTypesObject[string],
  run: RunNode as NodeTypesObject[string],
  session: GenericNode as NodeTypesObject[string],
  mission: GenericNode as NodeTypesObject[string],
  task: GenericNode as NodeTypesObject[string],
  flowstep: GenericNode as NodeTypesObject[string],
})

// ── Mission select options ────────────────────────────────────────────────────
const missionOptions = computed(() =>
  missions.value.map((m) => ({
    label: m.goal.length > 50 ? m.goal.slice(0, 47) + '…' : m.goal,
    value: m.id,
  })),
)

// ── Flow select options ───────────────────────────────────────────────────────
const flowOptions = computed(() =>
  flows.value.map((f) => ({
    label: f.goal.length > 50 ? f.goal.slice(0, 47) + '…' : f.goal,
    value: f.flow_id,
  })),
)

// ── Graph rebuild (called on viewMode/mission/flow change, NOT on drag — G9) ─
function rebuildGraph(
  currentRuns: RunMeta[],
  mailbox: ReturnType<typeof fetchMailbox> extends Promise<infer T> ? T : never,
  currentMissions: Mission[],
  currentFlows: Flow[],
) {
  let graph: { nodes: typeof nodes.value; edges: typeof edges.value }

  if (viewMode.value === 'timeline') {
    graph = buildTimeline(currentRuns, timelineRange.value)
  } else if (viewMode.value === 'flowdag') {
    const flow = currentFlows.find((f) => f.flow_id === selectedFlowId.value)
    graph = flow ? buildFlowDag(flow) : { nodes: [], edges: [] }
  } else if (viewMode.value === 'flow') {
    graph = buildExecutionFlow(currentRuns, mailbox as Parameters<typeof buildExecutionFlow>[1])
  } else if (viewMode.value === 'mission') {
    const mission = currentMissions.find((m) => m.id === selectedMissionId.value)
    graph = mission ? buildMissionDag(mission) : { nodes: [], edges: [] }
  } else {
    graph = buildSessionTree(currentRuns)
  }

  // G7: shallowRef — replace entire ref, not mutate
  nodes.value = graph.nodes
  edges.value = graph.edges

  // fitView after next tick
  setTimeout(() => { fitView({ padding: 0.15 }) }, 50)
}

// Cached mailbox for view mode switching without re-fetch
const cachedMailbox = ref<Parameters<typeof buildExecutionFlow>[1]>([])

async function loadAll() {
  const pid = profilesStore.activeProfile?.id
  if (!pid) return

  loading.value = true
  loadError.value = null

  try {
    const [fetchedRuns, mailbox, fetchedMissions, fetchedFlows] = await Promise.all([
      fetchRuns(pid, 200),
      fetchMailbox(pid, 200),
      fetchMissions(pid).catch(() => [] as Mission[]),
      fetchFlows(pid).catch(() => [] as Flow[]),
    ])
    runs.value = fetchedRuns
    cachedMailbox.value = mailbox
    missions.value = fetchedMissions
    flows.value = fetchedFlows

    if (fetchedMissions.length > 0 && !selectedMissionId.value) {
      selectedMissionId.value = fetchedMissions[0].id
    }
    if (fetchedFlows.length > 0 && !selectedFlowId.value) {
      selectedFlowId.value = fetchedFlows[0].flow_id
    }

    rebuildGraph(fetchedRuns, mailbox, fetchedMissions, fetchedFlows)
  } catch (err) {
    loadError.value = err instanceof Error ? err.message : String(err)
  } finally {
    loading.value = false
  }
}

// Watch view mode / selected mission / flow — G9: no recompute on drag, only here
watch(viewMode, () => {
  rebuildGraph(runs.value, cachedMailbox.value, missions.value, flows.value)
})

watch(timelineRange, () => {
  if (viewMode.value === 'timeline') {
    rebuildGraph(runs.value, cachedMailbox.value, missions.value, flows.value)
  }
})

watch(selectedMissionId, () => {
  if (viewMode.value === 'mission') {
    rebuildGraph(runs.value, cachedMailbox.value, missions.value, flows.value)
  }
})

watch(selectedFlowId, () => {
  if (viewMode.value === 'flowdag') {
    rebuildGraph(runs.value, cachedMailbox.value, missions.value, flows.value)
  }
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => { if (id) loadAll() },
  { immediate: true },
)

// ── Node click handler ────────────────────────────────────────────────────────
function onNodeClick({ node }: NodeMouseEvent) {
  const data = node.data as GraphNodeData
  selectedNodeData.value = data

  // Run node click → open trace drawer (lazy fetch via consoleStore)
  if (data.nodeType === 'run' && data.runId) {
    const run = runs.value.find((r) => r.run_id === data.runId)
    if (run) {
      const pid = profilesStore.activeProfile?.id
      if (pid) {
        consoleStore.selectRun(run, pid)
        drawerVisible.value = true
      }
    }
  }
}

function onCloseInfoPanel() {
  selectedNodeData.value = null
}

function onOpenRunFromPanel(runId: string) {
  const run = runs.value.find((r) => r.run_id === runId)
  if (!run) return
  const pid = profilesStore.activeProfile?.id
  if (!pid) return
  consoleStore.selectRun(run, pid)
  drawerVisible.value = true
  selectedNodeData.value = null
}

function onCloseDrawer() {
  drawerVisible.value = false
  consoleStore.closeRun()
}

function onLoadMore() {
  const pid = profilesStore.activeProfile?.id
  if (pid) consoleStore.loadMoreTrace(pid)
}

// ── Empty state description per view ─────────────────────────────────────────
const emptyDescription = computed(() => {
  if (viewMode.value === 'flowdag') return t('canvas.emptyFlowDescription')
  return t('canvas.emptyDescription')
})
</script>

<template>
  <div class="canvas-view">
    <!-- Header toolbar -->
    <header class="canvas-header">
      <h2 class="header-title">{{ t('canvas.title') }}</h2>

      <div class="header-controls">
        <!-- View mode segment -->
        <div class="segment-group">
          <button
            class="segment-btn"
            :class="{ active: viewMode === 'timeline' }"
            @click="viewMode = 'timeline'"
          >{{ t('canvas.viewTimeline') }}</button>
          <button
            class="segment-btn"
            :class="{ active: viewMode === 'flowdag' }"
            @click="viewMode = 'flowdag'"
          >{{ t('canvas.viewFlowDag') }}</button>
          <button
            class="segment-btn"
            :class="{ active: viewMode === 'mission' }"
            @click="viewMode = 'mission'"
          >{{ t('canvas.viewMission') }}</button>
          <button
            class="segment-btn"
            :class="{ active: viewMode === 'session' }"
            @click="viewMode = 'session'"
          >{{ t('canvas.viewSession') }}</button>
          <button
            class="segment-btn"
            :class="{ active: viewMode === 'flow' }"
            @click="viewMode = 'flow'"
          >{{ t('canvas.viewFlow') }}</button>
        </div>

        <!-- Timeline range filter (only in timeline mode) -->
        <div v-if="viewMode === 'timeline'" class="segment-group segment-group--sm">
          <button
            class="segment-btn"
            :class="{ active: timelineRange === '24h' }"
            @click="timelineRange = '24h'"
          >24h</button>
          <button
            class="segment-btn"
            :class="{ active: timelineRange === '7d' }"
            @click="timelineRange = '7d'"
          >7d</button>
          <button
            class="segment-btn"
            :class="{ active: timelineRange === 'all' }"
            @click="timelineRange = 'all'"
          >{{ t('canvas.rangeAll') }}</button>
        </div>

        <!-- Mission selector (only shown in mission mode) -->
        <NSelect
          v-if="viewMode === 'mission'"
          v-model:value="selectedMissionId"
          :options="missionOptions"
          :placeholder="t('canvas.selectMission')"
          size="small"
          style="width: 240px"
        />

        <!-- Flow selector (only shown in flowdag mode) -->
        <NSelect
          v-if="viewMode === 'flowdag'"
          v-model:value="selectedFlowId"
          :options="flowOptions"
          :placeholder="t('canvas.selectFlow')"
          size="small"
          style="width: 240px"
        />

        <!-- Refresh button -->
        <button class="icon-btn" :disabled="loading" @click="loadAll" :title="t('canvas.refresh')">
          <NIcon :size="16"><RefreshOutline /></NIcon>
        </button>
      </div>
    </header>

    <!-- Body -->
    <div class="canvas-body">
      <!-- No project selected -->
      <EmptyState
        v-if="!profilesStore.activeProfile"
        :title="t('canvas.noProject')"
        :description="t('canvas.noProjectDescription')"
      >
        <template #icon>
          <NIcon><FolderOpenOutline /></NIcon>
        </template>
      </EmptyState>

      <!-- Loading -->
      <div v-else-if="loading && nodes.length === 0" class="center-state">
        <NSpin size="medium" />
        <span class="center-label">{{ t('common.loading') }}</span>
      </div>

      <!-- Error -->
      <div v-else-if="loadError && nodes.length === 0" class="center-state">
        <NIcon size="24" color="var(--error)"><AlertCircleOutline /></NIcon>
        <span class="center-label error-text">{{ loadError }}</span>
        <button class="icon-btn" @click="loadAll">{{ t('common.retry') }}</button>
      </div>

      <!-- Empty graph — flow dag special message -->
      <EmptyState
        v-else-if="!loading && nodes.length === 0 && viewMode === 'flowdag'"
        :title="t('canvas.emptyTitle')"
        :description="t('canvas.emptyFlowDescription')"
      />

      <!-- Empty graph -->
      <EmptyState
        v-else-if="!loading && nodes.length === 0"
        :title="t('canvas.emptyTitle')"
        :description="emptyDescription"
      />

      <!-- Vue Flow canvas -->
      <div v-else class="flow-container">
        <!-- Swimlane labels for timeline mode -->
        <div v-if="viewMode === 'timeline'" class="swimlane-legend" aria-hidden="true">
          <span class="swimlane-hint">{{ t('canvas.timelineLegend') }}</span>
        </div>

        <VueFlow
          :nodes="nodes"
          :edges="edges"
          :node-types="nodeTypes"
          :only-render-visible-elements="useVisibleOnly"
          fit-view-on-init
          class="golem-flow"
          @node-click="onNodeClick"
        >
          <Background />
          <Controls />
        </VueFlow>

        <!-- Node info panel (scalar data only — G7) -->
        <NodeInfoPanel
          :data="selectedNodeData"
          @close="onCloseInfoPanel"
          @open-run="onOpenRunFromPanel"
        />
      </div>
    </div>

    <!-- Run detail drawer (reused from ConsoleView) -->
    <RunDetailDrawer
      :show="drawerVisible && !!consoleStore.selectedRun"
      :run="consoleStore.selectedRun"
      :trace-data="consoleStore.traceData"
      :trace-loading="consoleStore.traceLoading"
      :trace-error="consoleStore.traceError"
      :trace-appending="consoleStore.traceAppending"
      :project-id="profilesStore.activeProfile?.id ?? ''"
      @close="onCloseDrawer"
      @load-more="onLoadMore"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.canvas-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.canvas-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
  gap: 12px;
  flex-wrap: wrap;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
  white-space: nowrap;
}

.header-controls {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}

.segment-group {
  display: flex;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  overflow: hidden;

  &--sm .segment-btn {
    padding: 5px 8px;
  }
}

.segment-btn {
  padding: 5px 12px;
  font-size: 12px;
  font-weight: 500;
  background: none;
  border: none;
  border-right: 1px solid $border-color;
  cursor: pointer;
  color: $text-secondary;
  transition: background $transition-fast, color $transition-fast;

  &:last-child { border-right: none; }

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.06);
    color: $text-primary;
  }

  &.active {
    background: rgba(var(--accent-primary-rgb), 0.12);
    color: $accent-primary;
    font-weight: 600;
  }
}

.icon-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 6px 10px;
  background: none;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  cursor: pointer;
  color: $text-secondary;
  font-size: 12px;
  transition: all $transition-fast;

  &:hover:not(:disabled) {
    color: $text-primary;
    border-color: $accent-primary;
  }

  &:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
}

.canvas-body {
  flex: 1;
  min-height: 0;
  position: relative;
  display: flex;
  flex-direction: column;
}

.flow-container {
  flex: 1;
  min-height: 0;
  position: relative;
}

.golem-flow {
  width: 100%;
  height: 100%;
  background: $bg-secondary;
}

.swimlane-legend {
  position: absolute;
  top: 8px;
  left: 12px;
  z-index: 5;
  font-size: 11px;
  color: $text-muted;
  pointer-events: none;
}

.swimlane-hint {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  padding: 3px 8px;
}

.center-state {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  color: $text-muted;
  font-size: 14px;
}

.center-label {
  color: $text-muted;
  font-size: 13px;
}

.error-text {
  color: $error;
}
</style>
