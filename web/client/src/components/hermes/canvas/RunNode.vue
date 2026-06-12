<script setup lang="ts">
// G8: plain div only — no NCard or heavy components
import type { GraphNodeData } from '@/utils/canvas-graph'

const props = defineProps<{
  data: GraphNodeData
  selected?: boolean
}>()

const resultClass = (result: string | undefined) => {
  if (result === 'success') return 'result--success'
  if (result === 'error') return 'result--error'
  if (result === 'timeout') return 'result--timeout'
  return ''
}
</script>

<template>
  <div
    class="canvas-node canvas-node--run"
    :class="[resultClass(data.result), { selected: props.selected }]"
  >
    <div class="node-title">{{ data.soul ?? '' }}</div>
    <div class="node-sub">{{ data.runId?.slice(0, 8) }}</div>
    <div class="node-result" :class="resultClass(data.result)">{{ data.result }}</div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.canvas-node {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  padding: 6px 10px;
  min-width: 140px;
  font-size: 11px;
  cursor: pointer;
  user-select: none;
  transition: border-color $transition-fast, box-shadow $transition-fast;

  &:hover {
    border-color: $accent-muted;
  }

  &.selected {
    border-color: $accent-primary;
    box-shadow: 0 0 0 2px rgba(var(--accent-primary-rgb), 0.2);
  }
}

.canvas-node--run {
  &.result--success {
    border-left: 3px solid $success;
  }
  &.result--error {
    border-left: 3px solid $error;
  }
  &.result--timeout {
    border-left: 3px solid $warning;
  }
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
  font-family: $font-code;
  font-size: 10px;
  margin-bottom: 2px;
}

.node-result {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;

  &.result--success { color: $success; }
  &.result--error   { color: $error; }
  &.result--timeout { color: $warning; }
}
</style>
