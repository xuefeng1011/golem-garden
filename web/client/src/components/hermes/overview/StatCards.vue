<script setup lang="ts">
import { computed } from 'vue'
import { NIcon } from 'naive-ui'
import {
  CheckmarkDoneOutline,
  TrendingUpOutline,
  CashOutline,
  PeopleOutline,
} from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import type { ProjectOverview } from '@/api/hermes/overview'
import SkeletonCard from '@/components/common/SkeletonCard.vue'

const { t } = useI18n()

const props = defineProps<{
  overview?: ProjectOverview | null
  loading?: boolean
}>()

function formatCost(n: number): string {
  if (n === 0) return '$0.00'
  if (n < 0.01) return '<$0.01'
  return '$' + n.toFixed(2)
}

// semantic color for success rate: high → success, low → warning
const successRateClass = computed(() => {
  const ov = props.overview
  if (!ov || ov.total_tasks === 0) return ''
  if (ov.success_rate >= 70) return 'is-success'
  if (ov.success_rate < 40) return 'is-warning'
  return ''
})
</script>

<template>
  <div v-if="loading" class="stat-cards" data-testid="stat-skeleton">
    <SkeletonCard v-for="i in 4" :key="i" :rows="2" />
  </div>

  <div v-else-if="overview" class="stat-cards">
    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('overview.totalTasks') }}</span>
        <NIcon class="stat-icon" size="18"><CheckmarkDoneOutline /></NIcon>
      </div>
      <div class="stat-value">{{ overview.total_tasks }}</div>
    </div>
    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('overview.successRate') }}</span>
        <NIcon class="stat-icon" size="18"><TrendingUpOutline /></NIcon>
      </div>
      <div class="stat-value" :class="successRateClass" data-testid="success-rate">
        {{ overview.success_rate.toFixed(1) }}%
      </div>
    </div>
    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('overview.totalCost') }}</span>
        <NIcon class="stat-icon" size="18"><CashOutline /></NIcon>
      </div>
      <div class="stat-value">{{ formatCost(overview.total_cost_usd) }}</div>
    </div>
    <div class="stat-card">
      <div class="stat-top">
        <span class="stat-label">{{ t('overview.teamSize') }}</span>
        <NIcon class="stat-icon" size="18"><PeopleOutline /></NIcon>
      </div>
      <div class="stat-value">{{ overview.souls_count }}</div>
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

  &.is-success {
    color: $success;
  }

  &.is-warning {
    color: $warning;
  }
}
</style>
