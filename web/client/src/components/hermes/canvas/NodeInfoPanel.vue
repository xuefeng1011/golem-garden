<script setup lang="ts">
// G7: only scalar data shown — no large objects
import type { GraphNodeData } from '@/utils/canvas-graph'
import { fmtUsd } from '@/utils/format'

const props = defineProps<{
  data: GraphNodeData | null
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'openRun', runId: string): void
}>()

function fmtDuration(ms: number | undefined): string {
  if (ms === undefined) return '—'
  const sec = ms / 1000
  if (sec < 60) return sec.toFixed(1) + 's'
  return (sec / 60).toFixed(1) + 'm'
}
</script>

<template>
  <div v-if="data" class="info-panel">
    <div class="info-header">
      <span class="info-type">{{ data.nodeType }}</span>
      <button class="info-close" @click="emit('close')" aria-label="Close">✕</button>
    </div>

    <div class="info-title">{{ data.label }}</div>

    <!-- Soul-specific -->
    <template v-if="data.nodeType === 'soul'">
      <div class="info-row">
        <span class="info-key">Runs</span>
        <span class="info-val">{{ data.runCount }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Success rate</span>
        <span class="info-val">{{ data.successRate }}%</span>
      </div>
      <div class="info-row">
        <span class="info-key">Total cost</span>
        <span class="info-val">{{ fmtUsd(data.totalCost ?? null) }}</span>
      </div>
    </template>

    <!-- Run-specific -->
    <template v-else-if="data.nodeType === 'run'">
      <div class="info-row">
        <span class="info-key">Run ID</span>
        <span class="info-val mono">{{ data.runId?.slice(0, 16) }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">SOUL</span>
        <span class="info-val">{{ data.soul }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Result</span>
        <span class="info-val" :class="`result--${data.result}`">{{ data.result }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Duration</span>
        <span class="info-val">{{ fmtDuration(data.durationMs) }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Cost</span>
        <span class="info-val">{{ fmtUsd(data.costUsd ?? null) }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Model</span>
        <span class="info-val">{{ data.model }}</span>
      </div>
      <button
        v-if="data.runId"
        class="info-btn"
        @click="emit('openRun', data.runId!)"
      >
        Open trace
      </button>
    </template>

    <!-- Session-specific -->
    <template v-else-if="data.nodeType === 'session'">
      <div class="info-row">
        <span class="info-key">Session ID</span>
        <span class="info-val mono">{{ data.sessionId?.slice(0, 16) }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Runs</span>
        <span class="info-val">{{ data.childCount }}</span>
      </div>
    </template>

    <!-- Mission-specific -->
    <template v-else-if="data.nodeType === 'mission'">
      <div class="info-row">
        <span class="info-key">Mission ID</span>
        <span class="info-val mono">{{ data.missionId?.slice(0, 16) }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Status</span>
        <span class="info-val">{{ data.status }}</span>
      </div>
    </template>

    <!-- Task-specific -->
    <template v-else-if="data.nodeType === 'task'">
      <div class="info-row">
        <span class="info-key">SOUL</span>
        <span class="info-val">{{ data.soul }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Status</span>
        <span class="info-val">{{ data.status }}</span>
      </div>
      <div class="info-row">
        <span class="info-key">Task #</span>
        <span class="info-val">{{ data.taskIdx }}</span>
      </div>
    </template>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.info-panel {
  position: absolute;
  top: 12px;
  right: 12px;
  z-index: 10;
  width: 220px;
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  box-shadow: $shadow-md;
  padding: 12px;
  font-size: 12px;
}

.info-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 6px;
}

.info-type {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  color: $text-muted;
}

.info-close {
  background: none;
  border: none;
  cursor: pointer;
  color: $text-muted;
  font-size: 12px;
  padding: 0 2px;
  line-height: 1;

  &:hover { color: $text-primary; }
}

.info-title {
  font-weight: 600;
  color: $text-primary;
  margin-bottom: 10px;
  word-break: break-word;
  line-height: 1.4;
}

.info-row {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  padding: 3px 0;
  border-bottom: 1px solid $border-light;

  &:last-of-type { border-bottom: none; }
}

.info-key {
  color: $text-muted;
  flex-shrink: 0;
}

.info-val {
  color: $text-primary;
  text-align: right;
  word-break: break-all;

  &.mono { font-family: $font-code; font-size: 10px; }
  &.result--success { color: $success; font-weight: 600; }
  &.result--error   { color: $error;   font-weight: 600; }
  &.result--timeout { color: $warning; font-weight: 600; }
}

.info-btn {
  margin-top: 10px;
  width: 100%;
  padding: 6px;
  background: rgba(var(--accent-primary-rgb), 0.08);
  border: 1px solid rgba(var(--accent-primary-rgb), 0.2);
  border-radius: $radius-sm;
  color: $accent-primary;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  transition: background $transition-fast;

  &:hover {
    background: rgba(var(--accent-primary-rgb), 0.16);
  }
}
</style>
