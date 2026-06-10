<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { ChemistryPair } from '@/api/hermes/chemistry'

const props = withDefaults(
  defineProps<{
    pair: ChemistryPair
    maxScore?: number
  }>(),
  {
    maxScore: 0,
  },
)

const { t } = useI18n()

// 0..1 relative intensity vs. the team's best pair; accent the strong ones
const intensity = computed(() => {
  if (props.pair.score === null || props.maxScore <= 0) return 0
  return Math.min(1, props.pair.score / props.maxScore)
})

const accent = computed(() => intensity.value >= 0.7)

const scoreText = computed(() =>
  props.pair.score === null ? '—' : String(props.pair.score)
)
</script>

<template>
  <div class="pair-card" :class="{ 'pair-accent': accent }">
    <div class="pair-souls">
      <span class="soul-name">{{ pair.souls[0] }}</span>
      <span class="pair-x">×</span>
      <span class="soul-name">{{ pair.souls[1] }}</span>
    </div>
    <div class="pair-meta">
      <span class="score-badge" :class="{ 'score-accent': accent }">
        {{ t('team.chemistryScore') }} {{ scoreText }}
      </span>
      <span class="interactions">
        {{ t('team.chemistryCollabs', { n: pair.interactions }) }}
      </span>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.pair-card {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  box-shadow: var(--shadow-sm);
  transition: box-shadow $transition-fast, border-color $transition-fast;

  &:hover {
    box-shadow: var(--shadow-md);
  }

  &.pair-accent {
    border-color: rgba(var(--accent-primary-rgb), 0.5);
  }
}

.pair-souls {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
}

.soul-name {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pair-x {
  font-size: 11px;
  color: $text-muted;
  flex-shrink: 0;
}

.pair-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.score-badge {
  font-size: 11px;
  font-weight: 600;
  color: $text-secondary;
  background: $bg-secondary;
  border-radius: $radius-sm;
  padding: 2px 8px;
  white-space: nowrap;

  &.score-accent {
    color: $accent-primary;
    background: rgba(var(--accent-primary-rgb), 0.12);
  }
}

.interactions {
  font-size: 11px;
  color: $text-muted;
  white-space: nowrap;
}
</style>
