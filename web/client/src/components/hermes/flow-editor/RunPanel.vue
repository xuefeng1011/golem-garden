<script setup lang="ts">
/**
 * RunPanel — resizable bottom panel showing live forge stdout/stderr.
 * Groups output into collapsible per-step sections (via flow-run-log parser),
 * with a raw "전체 로그" fallback toggle. Approval/rejection buttons appear
 * for waiting_approval nodes.
 */
import { ref, watch, nextTick, onUnmounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { NButton, NIcon } from 'naive-ui'
import {
  ChevronDownOutline,
  ChevronUpOutline,
  CheckmarkOutline,
  CloseOutline,
  CheckmarkCircle,
  CloseCircle,
  PlayCircleOutline,
  ExpandOutline,
  ContractOutline,
} from '@vicons/ionicons5'
import type { FlowLogSection } from '@/utils/flow-run-log'

const props = defineProps<{
  lines: string[]
  sections: FlowLogSection[]
  currentStepId: string | null
  running: boolean
  phase?: 'idle' | 'running' | 'waiting' | 'done' | 'failed'
  waitingSteps: { stepId: string; label: string }[]
  // 현재 실행 중인 단계 라벨 — 레거시(마커 없음) 폴백용
  activeStep?: string
}>()

const emit = defineEmits<{
  (e: 'approve', stepId: string): void
  (e: 'reject', stepId: string): void
  (e: 'stop'): void
}>()

const { t } = useI18n()

const collapsed = ref(false)
const scrollEl = ref<HTMLElement | null>(null)
const viewMode = ref<'grouped' | 'raw'>('grouped')

// ── 패널 높이 (드래그 리사이즈 + localStorage 지속) ───────────────────────────
const HEIGHT_KEY = 'hermes_flow_runpanel_h'
const MIN_H = 120

function clampHeight(h: number): number {
  const maxH = window.innerHeight * 0.85
  return Math.max(MIN_H, Math.min(maxH, h))
}
function loadHeight(): number {
  try {
    const raw = Number(localStorage.getItem(HEIGHT_KEY))
    if (Number.isFinite(raw) && raw > 0) return clampHeight(raw)
  } catch { /* localStorage unavailable — fall through to default */ }
  return clampHeight(Math.round(window.innerHeight * 0.38))
}
const panelHeight = ref(loadHeight())
const expanded = ref(false)

let dragStartY = 0
let dragStartHeight = 0
function onHeightResizeStart(e: MouseEvent) {
  dragStartY = e.clientY
  dragStartHeight = panelHeight.value
  window.addEventListener('mousemove', onHeightResizeMove)
  window.addEventListener('mouseup', onHeightResizeEnd)
}
function onHeightResizeMove(e: MouseEvent) {
  panelHeight.value = clampHeight(dragStartHeight + (dragStartY - e.clientY))
}
function onHeightResizeEnd() {
  window.removeEventListener('mousemove', onHeightResizeMove)
  window.removeEventListener('mouseup', onHeightResizeEnd)
  try { localStorage.setItem(HEIGHT_KEY, String(panelHeight.value)) } catch { /* ignore */ }
}
onUnmounted(() => {
  window.removeEventListener('mousemove', onHeightResizeMove)
  window.removeEventListener('mouseup', onHeightResizeEnd)
})

function toggleExpand() {
  if (expanded.value) {
    panelHeight.value = loadHeight()
    expanded.value = false
  } else {
    panelHeight.value = clampHeight(Math.round(window.innerHeight * 0.7))
    expanded.value = true
  }
}

// 실행 시작 시 패널 자동 펼침 (진행 상황이 바로 보이도록) + 경과 시간 타이머
const elapsedSec = ref(0)
let elapsedTimer: ReturnType<typeof setInterval> | null = null
watch(
  () => props.running,
  (r) => {
    if (r) {
      collapsed.value = false
      elapsedSec.value = 0
      if (elapsedTimer) clearInterval(elapsedTimer)
      elapsedTimer = setInterval(() => { elapsedSec.value += 1 }, 1000)
    } else if (elapsedTimer) {
      clearInterval(elapsedTimer)
      elapsedTimer = null
    }
  },
)
onUnmounted(() => { if (elapsedTimer) clearInterval(elapsedTimer) })

const elapsedLabel = computed(() => {
  const s = elapsedSec.value
  const m = Math.floor(s / 60)
  return m > 0 ? `${m}m ${s % 60}s` : `${s}s`
})

// 결과 칩 — 실행 종료 후 단계 표시
const resultChip = computed(() => {
  switch (props.phase) {
    case 'done':    return { text: t('flowEditor.phaseDone'),    cls: 'chip-done' }
    case 'failed':  return { text: t('flowEditor.phaseFailed'),  cls: 'chip-failed' }
    case 'waiting': return { text: t('flowEditor.phaseWaiting'), cls: 'chip-waiting' }
    default:        return null
  }
})

// ── 현재 단계 표시 (스티키 헤더) ───────────────────────────────────────────
const currentStepInfo = computed(() => {
  const sec = props.sections.find((s) => s.kind === 'step' && s.stepId === props.currentStepId)
  if (sec) return { stepId: sec.stepId ?? '', soul: sec.soul ?? '' }
  if (props.activeStep) return { stepId: props.activeStep, soul: '' }
  return null
})

// ── 섹션 펼침 상태 ────────────────────────────────────────────────────────
// 기본 규칙: 진행 중엔 현재 단계만 열림, 종료 후엔 마지막 섹션이 열림.
// 사용자가 직접 클릭하면 그 선택이 규칙을 덮어쓴다.
const manualOverride = ref<Record<number, boolean>>({})

function isSectionOpen(idx: number): boolean {
  if (idx in manualOverride.value) return manualOverride.value[idx]
  const section = props.sections[idx]
  if (!section) return false
  if (section.kind === 'run' && props.sections.length === 1) return true
  if (props.running) return section.kind === 'step' && section.stepId === props.currentStepId
  return idx === props.sections.length - 1
}

function toggleSection(idx: number) {
  manualOverride.value = { ...manualOverride.value, [idx]: !isSectionOpen(idx) }
}

function sectionIcon(status: FlowLogSection['status']) {
  if (status === 'done') return CheckmarkCircle
  if (status === 'failed') return CloseCircle
  return PlayCircleOutline
}

// Auto-scroll to bottom when new output arrives (grouped or raw view).
const totalLineCount = computed(() =>
  viewMode.value === 'raw'
    ? props.lines.length
    : props.sections.reduce((n, s) => n + s.lines.length, 0),
)
watch(totalLineCount, async () => {
  if (collapsed.value) return
  await nextTick()
  if (scrollEl.value) scrollEl.value.scrollTop = scrollEl.value.scrollHeight
})
watch(() => props.sections.length, async () => {
  if (collapsed.value) return
  await nextTick()
  if (scrollEl.value) scrollEl.value.scrollTop = scrollEl.value.scrollHeight
})
</script>

<template>
  <div
    class="run-panel"
    :class="{ collapsed }"
    :style="collapsed ? undefined : { height: panelHeight + 'px' }"
  >
    <div v-if="!collapsed" class="resize-handle-top" :title="t('flowEditor.resizeHint')" @mousedown="onHeightResizeStart" />

    <div class="run-panel-header" @click="collapsed = !collapsed">
      <span class="run-panel-title">{{ t('flowEditor.runPanelTitle') }}</span>
      <span v-if="running" class="elapsed">{{ elapsedLabel }}</span>
      <span v-if="running" class="running-badge">{{ t('flowEditor.running') }}</span>
      <span v-else-if="resultChip" class="result-chip" :class="resultChip.cls">{{ resultChip.text }}</span>
      <button
        class="expand-btn"
        :title="expanded ? t('flowEditor.btnRestore') : t('flowEditor.btnExpand')"
        @click.stop="toggleExpand"
      >
        <NIcon :size="13"><ContractOutline v-if="expanded" /><ExpandOutline v-else /></NIcon>
      </button>
      <button
        v-if="running"
        class="stop-btn"
        :title="t('flowEditor.btnStop')"
        @click.stop="emit('stop')"
      >■ {{ t('flowEditor.btnStop') }}</button>
      <NIcon class="toggle-icon" :size="14">
        <ChevronUpOutline v-if="!collapsed" />
        <ChevronDownOutline v-else />
      </NIcon>
    </div>

    <div v-show="!collapsed" class="run-panel-body">
      <!-- Approval actions -->
      <div v-if="waitingSteps.length > 0" class="approval-bar">
        <span class="approval-label">{{ t('flowEditor.approvalPending') }}</span>
        <div v-for="step in waitingSteps" :key="step.stepId" class="approval-step">
          <span class="step-name">{{ step.label }}</span>
          <NButton size="tiny" type="success" @click="emit('approve', step.stepId)">
            <template #icon><NIcon><CheckmarkOutline /></NIcon></template>
            {{ t('flowEditor.btnApprove') }}
          </NButton>
          <NButton size="tiny" type="error" @click="emit('reject', step.stepId)">
            <template #icon><NIcon><CloseOutline /></NIcon></template>
            {{ t('flowEditor.btnReject') }}
          </NButton>
        </div>
      </div>

      <!-- 현재 단계 스티키 헤더 -->
      <div v-if="running && currentStepInfo" class="current-step-bar">
        <span v-if="currentStepInfo.soul">
          {{ t('flowEditor.currentStepLabel', { step: currentStepInfo.stepId, soul: currentStepInfo.soul }) }}
        </span>
        <span v-else>
          {{ t('flowEditor.currentStepLabelNoSoul', { step: currentStepInfo.stepId }) }}
        </span>
      </div>

      <!-- 보기 전환: 그룹별 / 전체 로그 -->
      <div class="view-toggle">
        <button :class="{ active: viewMode === 'grouped' }" @click="viewMode = 'grouped'">
          {{ t('flowEditor.viewGrouped') }}
        </button>
        <button :class="{ active: viewMode === 'raw' }" @click="viewMode = 'raw'">
          {{ t('flowEditor.viewRaw') }}
        </button>
      </div>

      <!-- Grouped view -->
      <div v-if="viewMode === 'grouped'" ref="scrollEl" class="sections-list">
        <div v-if="sections.length === 0" class="log-empty">{{ t('flowEditor.runLogEmpty') }}</div>
        <div
          v-for="(section, idx) in sections"
          :key="idx"
          class="log-section"
          :class="`section-${section.status}`"
        >
          <button class="section-header" @click="toggleSection(idx)">
            <NIcon class="section-status-icon" :class="`is-${section.status}`" :size="13">
              <component :is="sectionIcon(section.status)" />
            </NIcon>
            <span class="section-title">
              <template v-if="section.kind === 'step'">
                {{ section.stepId }}<span v-if="section.soul" class="section-soul">({{ section.soul }})</span>
              </template>
              <template v-else>{{ t('flowEditor.runPreamble') }}</template>
            </span>
            <span v-if="section.title" class="section-task-preview">{{ section.title }}</span>
            <NIcon class="section-chevron" :size="12">
              <ChevronUpOutline v-if="isSectionOpen(idx)" />
              <ChevronDownOutline v-else />
            </NIcon>
          </button>
          <div v-show="isSectionOpen(idx)" class="section-body">
            <div v-if="section.lines.length === 0" class="log-empty-inline">
              {{ t('flowEditor.sectionNoOutput') }}
            </div>
            <div v-for="(line, li) in section.lines" :key="li" class="log-line">{{ line }}</div>
          </div>
        </div>
      </div>

      <!-- Raw fallback view -->
      <div v-else ref="scrollEl" class="run-log">
        <div v-if="lines.length === 0" class="log-empty">{{ t('flowEditor.runLogEmpty') }}</div>
        <div v-for="(line, i) in lines" :key="i" class="log-line">{{ line }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.run-panel {
  flex-shrink: 0;
  border-top: 1px solid $border-color;
  background: $bg-secondary;
  display: flex;
  flex-direction: column;
  position: relative;

  &.collapsed {
    height: 36px;
  }
}

.resize-handle-top {
  position: absolute;
  top: -4px;
  left: 0;
  right: 0;
  height: 8px;
  cursor: ns-resize;
  z-index: 15;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.15);
  }
}

.run-panel-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  cursor: pointer;
  flex-shrink: 0;
  user-select: none;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.04);
  }
}

.run-panel-title {
  font-size: 12px;
  font-weight: 600;
  color: $text-primary;
  flex: 1;
}

.elapsed {
  font-size: 11px;
  color: $text-muted;
  font-variant-numeric: tabular-nums;
}

.running-badge {
  font-size: 11px;
  color: $accent-primary;
  background: rgba(var(--accent-primary-rgb), 0.12);
  border-radius: 10px;
  padding: 1px 8px;
  animation: pulse-opacity 1.4s ease-in-out infinite;
}

@keyframes pulse-opacity {
  0%, 100% { opacity: 1; }
  50%       { opacity: 0.5; }
}

.expand-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  background: none;
  border: 1px solid $border-color;
  border-radius: 6px;
  color: $text-muted;
  padding: 2px 5px;
  cursor: pointer;

  &:hover { color: $text-primary; border-color: $accent-primary; }
}

.stop-btn {
  font-size: 11px;
  font-weight: 600;
  color: $error;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 6px;
  padding: 1px 8px;
  cursor: pointer;

  &:hover { background: rgba(239, 68, 68, 0.18); }
}

.result-chip {
  font-size: 11px;
  font-weight: 600;
  border-radius: 10px;
  padding: 1px 8px;

  &.chip-done    { color: $success; background: rgba(34, 197, 94, 0.14); }
  &.chip-failed  { color: $error;   background: rgba(239, 68, 68, 0.14); }
  &.chip-waiting { color: $warning;  background: rgba(245, 158, 11, 0.16); }
}

.toggle-icon {
  color: $text-muted;
}

.run-panel-body {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.approval-bar {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  padding: 6px 14px;
  background: rgba(245, 158, 11, 0.08);
  border-bottom: 1px solid rgba(245, 158, 11, 0.2);
  flex-shrink: 0;
}

.approval-label {
  font-size: 12px;
  color: $warning;
  font-weight: 600;
}

.approval-step {
  display: flex;
  align-items: center;
  gap: 4px;
}

.step-name {
  font-size: 11px;
  color: $text-secondary;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.current-step-bar {
  flex-shrink: 0;
  padding: 5px 14px;
  font-size: 12px;
  font-weight: 600;
  color: $accent-primary;
  background: rgba(var(--accent-primary-rgb), 0.08);
  border-bottom: 1px solid rgba(var(--accent-primary-rgb), 0.16);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.view-toggle {
  display: flex;
  gap: 4px;
  padding: 6px 14px 0;
  flex-shrink: 0;

  button {
    font-size: 11px;
    font-weight: 500;
    color: $text-muted;
    background: none;
    border: 1px solid $border-color;
    border-radius: 6px;
    padding: 3px 10px;
    cursor: pointer;

    &.active {
      color: $accent-primary;
      border-color: $accent-primary;
      background: rgba(var(--accent-primary-rgb), 0.08);
    }
  }
}

.sections-list,
.run-log {
  flex: 1;
  overflow-y: auto;
  padding: 8px 14px 10px;
  font-family: $font-code;
  font-size: 12px;
  line-height: 1.6;
}

.log-empty {
  color: $text-muted;
  font-style: italic;
  padding-top: 4px;
}

.log-empty-inline {
  color: $text-muted;
  font-style: italic;
  font-size: 11px;
  padding: 2px 0 4px;
}

.log-line {
  color: $text-secondary;
  white-space: pre-wrap;
  word-break: break-all;
}

// ── 그룹 섹션 ─────────────────────────────────────────────────
.log-section {
  border: 1px solid $border-color;
  border-radius: 8px;
  margin-bottom: 6px;
  overflow: hidden;
  background: $bg-card;

  &.section-running {
    border-color: rgba(var(--accent-primary-rgb), 0.35);
  }
  &.section-failed {
    border-color: rgba(var(--error-rgb), 0.35);
  }
}

.section-header {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
  padding: 5px 10px;
  background: none;
  border: none;
  cursor: pointer;
  text-align: left;
  font-family: inherit;

  &:hover { background: rgba(var(--accent-primary-rgb), 0.04); }
}

.section-status-icon {
  flex-shrink: 0;
  color: $text-muted;

  &.is-done    { color: $success; }
  &.is-failed  { color: $error; }
  &.is-running { color: $accent-primary; animation: pulse-opacity 1.2s ease-in-out infinite; }
}

.section-title {
  flex-shrink: 0;
  font-size: 12px;
  font-weight: 600;
  color: $text-primary;
}

.section-soul {
  font-weight: 400;
  color: $text-muted;
  margin-left: 3px;
}

.section-task-preview {
  flex: 1;
  min-width: 0;
  font-size: 11px;
  color: $text-muted;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.section-chevron {
  flex-shrink: 0;
  color: $text-muted;
}

.section-body {
  padding: 4px 10px 8px 30px;
  border-top: 1px solid $border-color;
}
</style>
