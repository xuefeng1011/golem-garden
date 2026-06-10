<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  current: string
  next?: string | null
  tasksToPromote?: number
}>()

const { t } = useI18n()

const RANK_ORDER = ['novice', 'junior', 'senior', 'master'] as const

const normalizedCurrent = computed(() => props.current.toLowerCase())

const isMaxRank = computed(
  () => !props.next || normalizedCurrent.value === 'master',
)

const progressPercent = computed(() => {
  if (isMaxRank.value) return 100
  const index = RANK_ORDER.indexOf(
    normalizedCurrent.value as (typeof RANK_ORDER)[number],
  )
  if (index < 0) return 0
  return Math.round(((index + 1) / RANK_ORDER.length) * 100)
})

const caption = computed(() => {
  if (isMaxRank.value) return t('common.maxRank')
  if (props.tasksToPromote === undefined) return ''
  return t('common.tasksToPromote', { n: props.tasksToPromote })
})
</script>

<template>
  <div class="rank-progress">
    <div class="rank-row">
      <span class="rank-badge" :class="`rank-${normalizedCurrent}`">
        {{ current }}
      </span>
      <span v-if="next && !isMaxRank" class="rank-arrow" aria-hidden="true">&rarr;</span>
      <span
        v-if="next && !isMaxRank"
        class="rank-badge rank-next"
        :class="`rank-${next.toLowerCase()}`"
      >
        {{ next }}
      </span>
    </div>

    <div
      class="progress-track"
      role="progressbar"
      :aria-valuenow="progressPercent"
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div
        class="progress-fill"
        :class="{ 'progress-max': isMaxRank }"
        :style="{ width: `${progressPercent}%` }"
      />
    </div>

    <p v-if="caption" class="progress-caption">{{ caption }}</p>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.rank-progress {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.rank-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.rank-badge {
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

.rank-next {
  opacity: 0.65;
}

.rank-arrow {
  font-size: 12px;
  color: $text-muted;
}

.progress-track {
  height: 6px;
  border-radius: 3px;
  background: rgba(var(--text-muted-rgb), 0.18);
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  border-radius: 3px;
  background: $accent-primary;
  transition: width 0.25s var(--ease-out);

  &.progress-max {
    background: #9b59b6;
  }
}

.progress-caption {
  font-size: 12px;
  color: $text-muted;
  margin: 0;
}
</style>
