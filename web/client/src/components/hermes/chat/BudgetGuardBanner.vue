<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { ProjectBudget } from '@/api/hermes/budget'

const props = defineProps<{
  budget: ProjectBudget | null
}>()

const { t } = useI18n()

const dismissed = ref(false)

const usagePercent = computed<number | null>(() => {
  if (!props.budget || !props.budget.budget_limit_usd) return null
  return (props.budget.total_cost_usd / props.budget.budget_limit_usd) * 100
})

// Only show when budget_limit_usd is set AND usage >= 80%
const visible = computed(() => {
  if (dismissed.value) return false
  if (!props.budget || !props.budget.budget_limit_usd) return false
  return (
    (props.budget.warning != null && props.budget.warning !== '') ||
    (usagePercent.value !== null && usagePercent.value >= 80)
  )
})

const isBlocked = computed(() => {
  if (!visible.value) return false
  return usagePercent.value !== null && usagePercent.value >= 100
})

const pct = computed(() =>
  usagePercent.value !== null ? usagePercent.value.toFixed(1) : '0.0',
)
</script>

<template>
  <div
    v-if="visible"
    class="budget-guard-banner"
    :class="isBlocked ? 'banner--blocked' : 'banner--warning'"
    role="alert"
  >
    <span class="banner-icon">{{ isBlocked ? '🚫' : '⚠️' }}</span>
    <span class="banner-text">
      <template v-if="isBlocked">
        {{ t('chat.budgetBlocked') }}
      </template>
      <template v-else>
        {{ t('chat.budgetWarning', { pct }) }}
      </template>
    </span>
    <button class="banner-dismiss" :aria-label="t('common.cancel')" @click="dismissed = true">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <line x1="18" y1="6" x2="6" y2="18" />
        <line x1="6" y1="6" x2="18" y2="18" />
      </svg>
    </button>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.budget-guard-banner {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 14px;
  font-size: 13px;
  font-weight: 500;
  flex-shrink: 0;
  border-bottom: 1px solid transparent;

  &.banner--warning {
    background: rgba(var(--warning-rgb), 0.10);
    border-color: rgba(var(--warning-rgb), 0.25);
    color: $warning;
  }

  &.banner--blocked {
    background: rgba(var(--error-rgb), 0.10);
    border-color: rgba(var(--error-rgb), 0.25);
    color: $error;
  }
}

.banner-icon {
  flex-shrink: 0;
  font-size: 14px;
}

.banner-text {
  flex: 1;
  line-height: 1.4;
}

.banner-dismiss {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: none;
  cursor: pointer;
  padding: 2px;
  border-radius: $radius-sm;
  color: inherit;
  opacity: 0.6;
  transition: opacity $transition-fast;

  &:hover {
    opacity: 1;
  }
}
</style>
