<script setup lang="ts">
/**
 * N8nNode — 단일 n8n 스타일 노드 (모든 nodeType 처리)
 * G8: plain div + SVG 아이콘(@vicons)만. Naive UI 컴포넌트 미사용.
 * 좌측 아이콘 칩(SOUL 이니셜 또는 타입 아이콘) + 제목 + 부제 + 상태 점.
 * 좌(target)/우(source) Handle 로 좌→우 흐름. 디테일은 클릭 시 NodeInfoPanel.
 */
import { computed } from 'vue'
import { Handle, Position } from '@vue-flow/core'
import {
  HardwareChipOutline,
  PlayCircleOutline,
  LayersOutline,
  FlagOutline,
  GitCommitOutline,
  LockClosedOutline,
} from '@vicons/ionicons5'
import type { GraphNodeData } from '@/utils/canvas-graph'

const props = defineProps<{
  data: GraphNodeData
  selected?: boolean
}>()

// status(있으면) 또는 run 의 result 를 통일된 상태 키로 정규화
const statusKey = computed(() => {
  const s = props.data.status
  if (s) {
    if (s === 'done' || s === 'completed') return 'done'
    if (s === 'failed' || s === 'error') return 'failed'
    if (s === 'running' || s === 'in_progress') return 'running'
    if (s === 'waiting_approval') return 'waiting'
    if (s === 'skipped') return 'skipped'
    return 'pending'
  }
  const r = props.data.result
  if (r === 'success') return 'done'
  if (r === 'error') return 'failed'
  if (r === 'timeout') return 'waiting'
  return ''
})

// 아이콘 칩: soul 이 있으면 이니셜 아바타, 없으면 타입 아이콘
const soulInitial = computed(() => {
  const s = props.data.soul
  return s && s.length > 0 ? s[0].toUpperCase() : ''
})

const typeIcon = computed(() => {
  switch (props.data.nodeType) {
    case 'soul': return HardwareChipOutline
    case 'run': return PlayCircleOutline
    case 'session': return LayersOutline
    case 'mission': return FlagOutline
    default: return GitCommitOutline
  }
})

const subtitle = computed(() => {
  const d = props.data
  switch (d.nodeType) {
    case 'soul':
      return d.runCount !== undefined
        ? `${d.runCount} runs · ${d.successRate ?? 0}%`
        : ''
    case 'run':
      return d.model ?? ''
    case 'session':
      return d.childCount !== undefined ? `${d.childCount} runs` : ''
    case 'mission':
      return d.status ?? ''
    case 'task':
      return d.soul && d.soul.length > 0 ? d.soul : '(host)'
    default:
      return ''
  }
})
</script>

<template>
  <div
    class="n8n-node"
    :class="[`is-${statusKey}`, { selected: props.selected }]"
  >
    <Handle type="target" :position="Position.Left" class="n8n-handle" />

    <div class="node-icon" :class="[`icon-${data.nodeType}`, `is-${statusKey}`]">
      <span v-if="soulInitial" class="icon-initial">{{ soulInitial }}</span>
      <component :is="typeIcon" v-else class="icon-svg" />
    </div>

    <div class="node-body">
      <div class="node-title">{{ data.label }}</div>
      <div v-if="subtitle" class="node-sub">{{ subtitle }}</div>
    </div>

    <span v-if="data.approval" class="node-lock" title="approval gate">
      <LockClosedOutline class="lock-svg" />
    </span>
    <span v-if="statusKey" class="node-dot" :class="`is-${statusKey}`" />

    <Handle type="source" :position="Position.Right" class="n8n-handle" />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.n8n-node {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 210px;
  padding: 10px 12px;
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: 10px;
  box-shadow: $shadow-sm;
  cursor: pointer;
  user-select: none;
  position: relative;
  transition: border-color $transition-fast, box-shadow $transition-fast;

  &:hover {
    border-color: $accent-primary;
    box-shadow: $shadow-md;
  }

  &.selected {
    border-color: $accent-primary;
    box-shadow: 0 0 0 2px rgba(var(--accent-primary-rgb), 0.25);
  }

  // 실행 중 노드 강조 — 옅은 글로우 (G8: plain div 유지)
  &.is-running {
    border-color: $accent-primary;
    box-shadow: 0 0 0 3px rgba(var(--accent-primary-rgb), 0.18);
  }
}

// ── 아이콘 칩 ──────────────────────────────────────────────
.node-icon {
  flex-shrink: 0;
  width: 34px;
  height: 34px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(var(--accent-primary-rgb), 0.1);
  color: $accent-primary;

  &.is-done    { background: rgba(34, 197, 94, 0.14);  color: $success; }
  &.is-failed  { background: rgba(239, 68, 68, 0.14);  color: $error; }
  &.is-running { background: rgba(59, 130, 246, 0.14); color: $accent-primary; }
  &.is-waiting { background: rgba(245, 158, 11, 0.16); color: $warning; }
  &.is-skipped { background: rgba(148, 163, 184, 0.16); color: $text-muted; }
}

.icon-initial {
  font-size: 15px;
  font-weight: 700;
  line-height: 1;
}

.icon-svg {
  width: 18px;
  height: 18px;
}

// ── 본문 ─────────────────────────────────────────────────
.node-body {
  min-width: 0;
  flex: 1;
}

.node-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.node-sub {
  font-size: 11px;
  color: $text-muted;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-top: 1px;
}

// ── 상태 점 / 자물쇠 ─────────────────────────────────────
.node-dot {
  position: absolute;
  top: 8px;
  right: 8px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: $text-muted;

  &.is-done    { background: $success; }
  &.is-failed  { background: $error; }
  &.is-running {
    background: $accent-primary;
    animation: dot-pulse 1.2s ease-in-out infinite;
  }
  &.is-waiting { background: $warning; }
  &.is-skipped { background: $border-color; }
}

@keyframes dot-pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50%      { opacity: 0.4; transform: scale(0.7); }
}

.node-lock {
  position: absolute;
  top: 6px;
  right: 20px;
  color: $warning;
  display: flex;
}

.lock-svg {
  width: 12px;
  height: 12px;
}

// ── Handle (n8n 식 작은 원) ──────────────────────────────
.n8n-handle {
  width: 8px;
  height: 8px;
  background: $bg-card;
  border: 1.5px solid $border-color;
}
</style>
