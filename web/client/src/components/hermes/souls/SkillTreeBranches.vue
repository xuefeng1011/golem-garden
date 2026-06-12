<script setup lang="ts">
import type { SkillBranch } from '@/api/hermes/souls'

defineProps<{
  branches: SkillBranch[]
}>()

const MAX_LEVEL = 5

function dots(level: number): { filled: boolean }[] {
  return Array.from({ length: MAX_LEVEL }, (_, i) => ({ filled: i < level }))
}
</script>

<template>
  <div class="skill-tree-branches">
    <div
      v-for="branch in branches"
      :key="branch.name"
      class="branch-row"
    >
      <span class="branch-name">{{ branch.name }}</span>
      <span class="branch-dots" :aria-label="`level ${branch.level} of ${MAX_LEVEL}`">
        <span
          v-for="(dot, i) in dots(branch.level)"
          :key="i"
          class="dot"
          :class="{ filled: dot.filled }"
        />
      </span>
      <span class="branch-count">{{ branch.demonstrated_count }}</span>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.skill-tree-branches {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.branch-row {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
}

.branch-name {
  flex: 1;
  color: $text-secondary;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.branch-dots {
  display: flex;
  gap: 3px;
  flex-shrink: 0;
}

.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: $border-color;

  &.filled {
    background: $accent-primary;
  }
}

.branch-count {
  flex-shrink: 0;
  min-width: 28px;
  text-align: right;
  color: $text-muted;
  font-size: 11px;
}
</style>
