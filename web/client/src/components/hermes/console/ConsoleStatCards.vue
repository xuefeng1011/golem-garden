<script setup lang="ts">
import { computed } from 'vue'
import { NIcon } from 'naive-ui'
import {
  CheckmarkDoneOutline,
  TrendingUpOutline,
  CashOutline,
  TimerOutline,
} from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import type { ConsoleStats } from '@/api/hermes/console'
import type { ProjectBudget } from '@/api/hermes/budget'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import { fmtUsd } from '@/utils/format'

const { t } = useI18n()

const props = defineProps<{
  stats?: ConsoleStats | null
  budget?: ProjectBudget | null
  loading?: boolean
}>()

const successRateClass = computed(() => {
  const s = props.stats
  if (!s || s.total_runs === 0) return ''
  if (s.success_rate >= 70) return 'is-success'
  if (s.success_rate < 40) return 'is-warning'
  return ''
})

const avgDurationSec = computed(() => {
  const s = props.stats
  if (!s) return '—'
  return (s.avg_duration_ms / 1000).toFixed(1) + 's'
})

const budgetWarning = computed(() => props.budget?.warning ?? null)
</script>

<template>
  <div v-if="loading" class="stat-cards" data-testid="console-stat-skeleton">
    <SkeletonCard v-for="i in 4" :key="i" :rows="2" />
  </div>

  <div v-else-if="stats" class="stat-cards">
    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('console.totalRuns') }}</span>
        <NIcon class="stat-icon" size="18"><CheckmarkDoneOutline /></NIcon>
      </div>
      <div class="stat-value">{{ stats.total_runs }}</div>
    </div>

    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('console.successRate') }}</span>
        <NIcon class="stat-icon" size="18"><TrendingUpOutline /></NIcon>
      </div>
      <div class="stat-value" :class="successRateClass">
        {{ stats.success_rate.toFixed(1) }}%
      </div>
    </div>

    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('console.avgDuration') }}</span>
        <NIcon class="stat-icon" size="18"><TimerOutline /></NIcon>
      </div>
      <div class="stat-value">{{ avgDurationSec }}</div>
    </div>

    <div class="stat-card" :class="{ 'has-warning': budgetWarning }">
      <div class="stat-top">
        <span class="stat-label">{{ t('console.totalCost') }}</span>
        <NIcon class="stat-icon" size="18"><CashOutline /></NIcon>
      </div>
      <div class="stat-value">{{ fmtUsd(stats.total_cost_usd) }}</div>
      <div v-if="budgetWarning" class="budget-warning">{{ budgetWarning }}</div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.stat-cards {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  margin-bottom: 20px;

  @media (max-width: 768px) {
    grid-template-columns: repeat(2, 1fr);
  }
}

.stat-card {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px;
  transition: box-shadow 0.2s $ease-out, border-color 0.2s $ease-out;

  &:hover {
    border-color: rgba(var(--accent-primary-rgb), 0.35);
    box-shadow: $shadow-md;
  }

  &.has-warning {
    border-color: $warning;
  }
}

.stat-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

.stat-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.4px;
}

.stat-icon {
  color: $text-muted;
  opacity: 0.7;
  flex-shrink: 0;
}

.stat-value {
  font-size: 26px;
  font-weight: 700;
  color: $text-primary;
  line-height: 1.15;
  font-variant-numeric: tabular-nums;

  &.is-success { color: $success; }
  &.is-warning { color: $warning; }
}

.budget-warning {
  font-size: 11px;
  color: $warning;
  margin-top: 4px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
