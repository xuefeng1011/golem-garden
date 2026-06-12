<script setup lang="ts">
// G8: plain div only — no NCard or heavy components
import type { GraphNodeData } from '@/utils/canvas-graph'
import { fmtUsd } from '@/utils/format'

const props = defineProps<{
  data: GraphNodeData
  selected?: boolean
}>()
</script>

<template>
  <div class="canvas-node canvas-node--soul" :class="{ selected: props.selected }">
    <div class="node-title">{{ data.soul ?? data.label }}</div>
    <div class="node-stats">
      <span class="stat">{{ data.runCount }} runs</span>
      <span class="stat">{{ data.successRate }}%</span>
      <span class="stat">{{ fmtUsd(data.totalCost ?? null) }}</span>
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

.canvas-node--soul {
  border-top: 3px solid $accent-primary;
}

.node-title {
  font-weight: 600;
  color: $text-primary;
  margin-bottom: 4px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.node-stats {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.stat {
  color: $text-muted;
  font-size: 11px;
}
</style>
