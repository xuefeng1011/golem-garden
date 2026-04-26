<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { ProjectOverview } from '@/api/hermes/overview'

const { t } = useI18n()

defineProps<{ overview: ProjectOverview }>()

function formatCost(n: number): string {
  if (n === 0) return '$0.00'
  if (n < 0.01) return '<$0.01'
  return '$' + n.toFixed(2)
}
</script>

<template>
  <div class="stat-cards">
    <div class="stat-card">
      <div class="stat-label">{{ t('overview.totalTasks') }}</div>
      <div class="stat-value">{{ overview.total_tasks }}</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">{{ t('overview.successRate') }}</div>
      <div class="stat-value">{{ overview.success_rate.toFixed(1) }}%</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">{{ t('overview.totalCost') }}</div>
      <div class="stat-value">{{ formatCost(overview.total_cost_usd) }}</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">{{ t('overview.teamSize') }}</div>
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
}

.stat-label {
  font-size: 12px;
  color: $text-muted;
  margin-bottom: 6px;
}

.stat-value {
  font-size: 22px;
  font-weight: 600;
  color: $text-primary;
  line-height: 1.2;
}
</style>
