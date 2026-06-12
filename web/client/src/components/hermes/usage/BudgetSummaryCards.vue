<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import type { ProjectBudget } from '@/api/hermes/budget'
import { fmtUsd } from '@/utils/format'

const props = defineProps<{
  budget: ProjectBudget
}>()

const { t } = useI18n()

const usagePercent = computed(() => {
  if (!props.budget.budget_limit_usd) return null
  return (props.budget.total_cost_usd / props.budget.budget_limit_usd) * 100
})

const totalTasks = computed(() =>
  props.budget.by_soul.reduce((sum, row) => sum + row.tasks, 0)
)
</script>

<template>
  <div class="summary-cards">
    <div class="stat-card">
      <div class="stat-label">{{ t('usage.totalCost') }}</div>
      <div class="stat-value">{{ fmtUsd(budget.total_cost_usd) }}</div>
    </div>

    <div class="stat-card">
      <div class="stat-label">
        {{ t('usage.budgetUsage') }}
        <span v-if="budget.warning" class="warning-badge" :title="budget.warning">
          {{ t('usage.warningBadge') }}
        </span>
      </div>
      <template v-if="usagePercent !== null">
        <div class="stat-value" :class="{ 'stat-warn': budget.warning }">
          {{ usagePercent.toFixed(1) }}%
        </div>
        <div class="stat-sub">
          {{ t('usage.ofLimit', { limit: fmtUsd(budget.budget_limit_usd) }) }}
        </div>
      </template>
      <div v-else class="stat-value stat-muted">{{ t('usage.noLimit') }}</div>
    </div>

    <div class="stat-card">
      <div class="stat-label">{{ t('usage.totalTasks') }}</div>
      <div class="stat-value">{{ totalTasks }}</div>
    </div>

    <div class="stat-card">
      <div class="stat-label">{{ t('usage.activeSouls') }}</div>
      <div class="stat-value">{{ budget.by_soul.length }}</div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.summary-cards {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;

  @media (max-width: 768px) {
    grid-template-columns: repeat(2, 1fr);
  }
}

.stat-card {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px;
  box-shadow: var(--shadow-sm);
}

.stat-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: $text-muted;
  margin-bottom: 6px;
}

.stat-value {
  font-size: 22px;
  font-weight: 600;
  color: $text-primary;
  line-height: 1.2;

  &.stat-warn {
    color: $warning;
  }

  &.stat-muted {
    font-size: 16px;
    color: $text-muted;
  }
}

.stat-sub {
  font-size: 11px;
  color: $text-muted;
  margin-top: 4px;
}

.warning-badge {
  font-size: 10px;
  font-weight: 600;
  color: $warning;
  background: rgba(var(--warning-rgb), 0.12);
  border-radius: $radius-sm;
  padding: 1px 6px;
  white-space: nowrap;
}
</style>
