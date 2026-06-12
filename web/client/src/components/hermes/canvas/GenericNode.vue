<script setup lang="ts">
// G8: plain div — used for session, mission, task nodes
import type { GraphNodeData } from '@/utils/canvas-graph'

const props = defineProps<{
  data: GraphNodeData
  selected?: boolean
}>()

const statusClass = (status: string | undefined) => {
  if (status === 'completed' || status === 'done') return 'status--done'
  if (status === 'failed' || status === 'error') return 'status--error'
  if (status === 'running' || status === 'in_progress') return 'status--running'
  return ''
}
</script>

<template>
  <div
    class="canvas-node"
    :class="[`canvas-node--${data.nodeType}`, statusClass(data.status), { selected: props.selected }]"
  >
    <div class="node-type-badge">{{ data.nodeType }}</div>
    <div class="node-title">{{ data.label }}</div>
    <div v-if="data.soul" class="node-sub">{{ data.soul }}</div>
    <div v-if="data.status" class="node-status" :class="statusClass(data.status)">
      {{ data.status }}
    </div>
    <div v-if="data.childCount !== undefined" class="node-sub">
      {{ data.childCount }} runs
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.canvas-node {
  background: $bg-card;
  border: 1.5px solid $border-color;
  border-radius: $radius-md;
  padding: 8px 12px;
  min-width: 160px;
  max-width: 220px;
  font-size: 12px;
  cursor: pointer;
  user-select: none;
  transition: border-color $transition-fast, box-shadow $transition-fast;

  &:hover {
    border-color: $accent-primary;
  }

  &.selected {
    border-color: $accent-primary;
    box-shadow: 0 0 0 2px rgba(var(--accent-primary-rgb), 0.2);
  }
}

.canvas-node--session {
  border-top: 3px solid var(--accent-info);
}

.canvas-node--mission {
  border-top: 3px solid $warning;
}

.canvas-node--task {
  border-top: 3px solid $border-color;

  &.status--done    { border-top-color: $success; }
  &.status--error   { border-top-color: $error; }
  &.status--running { border-top-color: $accent-primary; }
}

.node-type-badge {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  color: $text-muted;
  margin-bottom: 3px;
}

.node-title {
  font-weight: 600;
  color: $text-primary;
  margin-bottom: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.node-sub {
  color: $text-muted;
  font-size: 10px;
}

.node-status {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  margin-top: 2px;

  &.status--done    { color: $success; }
  &.status--error   { color: $error; }
  &.status--running { color: $accent-primary; }
}
</style>
