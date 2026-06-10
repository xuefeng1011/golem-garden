<script setup lang="ts">
import type { Component } from 'vue'
import { NButton } from 'naive-ui'

export interface EmptyStateAction {
  label: string
  handler: () => void
}

defineProps<{
  title: string
  description?: string
  icon?: Component
  action?: EmptyStateAction
}>()
</script>

<template>
  <div class="empty-state" role="status">
    <div v-if="$slots.icon || icon" class="empty-icon">
      <slot name="icon">
        <component :is="icon" />
      </slot>
    </div>
    <p class="empty-title">{{ title }}</p>
    <p v-if="description" class="empty-description">{{ description }}</p>
    <NButton
      v-if="action"
      size="small"
      secondary
      class="empty-action"
      @click="action.handler"
    >
      {{ action.label }}
    </NButton>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 40px 20px;
  gap: 8px;
}

.empty-icon {
  font-size: 28px;
  line-height: 1;
  color: $text-muted;
  margin-bottom: 4px;

  :deep(svg) {
    width: 32px;
    height: 32px;
  }
}

.empty-title {
  font-size: 14px;
  font-weight: 600;
  color: $text-secondary;
  margin: 0;
}

.empty-description {
  font-size: 13px;
  color: $text-muted;
  margin: 0;
  max-width: 360px;
  line-height: 1.5;
}

.empty-action {
  margin-top: 8px;
}
</style>
