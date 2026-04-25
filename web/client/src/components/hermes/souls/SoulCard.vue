<script setup lang="ts">
import { NTag } from 'naive-ui'
import type { Soul } from '@/api/hermes/souls'

defineProps<{ soul: Soul }>()
defineEmits<{ (e: 'click'): void }>()
</script>

<template>
  <div class="soul-card" @click="$emit('click')">
    <div class="card-header">
      <h3 class="soul-name">{{ soul.name }}</h3>
      <span class="rank-tag" :class="`rank-${soul.rank}`">{{ soul.rank }}</span>
    </div>

    <p class="soul-description">{{ soul.description }}</p>

    <div v-if="soul.specialty?.length" class="specialty-chips">
      <NTag
        v-for="spec in soul.specialty.slice(0, 4)"
        :key="spec"
        size="small"
        :bordered="false"
        class="specialty-tag"
      >
        {{ spec }}
      </NTag>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.soul-card {
  background-color: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px;
  cursor: pointer;
  transition: border-color $transition-fast, box-shadow $transition-fast;

  &:hover {
    border-color: rgba(var(--accent-primary-rgb), 0.4);
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.08);
  }
}

.card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

.soul-name {
  font-size: 15px;
  font-weight: 600;
  color: $text-primary;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 70%;
}

.rank-tag {
  font-size: 11px;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: $radius-sm;
  text-transform: capitalize;

  &.rank-novice  { color: #888888; background: rgba(136, 136, 136, 0.12); }
  &.rank-junior  { color: #4a90d9; background: rgba(74, 144, 217, 0.12); }
  &.rank-senior  { color: #52a770; background: rgba(82, 167, 112, 0.12); }
  &.rank-master  { color: #9b59b6; background: rgba(155, 89, 182, 0.12); }
}

.soul-description {
  font-size: 13px;
  color: $text-secondary;
  line-height: 1.5;
  margin: 0 0 12px;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.specialty-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.specialty-tag {
  font-size: 11px;
}
</style>
