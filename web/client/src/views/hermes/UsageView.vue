<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { NAlert, NButton } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchBudget } from '@/api/hermes/budget'
import type { ProjectBudget } from '@/api/hermes/budget'
import BudgetSummaryCards from '@/components/hermes/usage/BudgetSummaryCards.vue'
import MiniBarChart from '@/components/common/MiniBarChart.vue'
import type { BarDatum } from '@/components/common/MiniBarChart.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import { fmtUsd } from '@/utils/format'

const { t } = useI18n()
const profilesStore = useProfilesStore()

const budget = ref<ProjectBudget | null>(null)
const loading = ref(false)
const error = ref(false)

async function loadBudget(projectId: string) {
  loading.value = true
  error.value = false
  try {
    budget.value = await fetchBudget(projectId)
  } catch {
    error.value = true
    budget.value = null
  } finally {
    loading.value = false
  }
}

function reload() {
  if (profilesStore.activeProfile?.id) {
    loadBudget(profilesStore.activeProfile.id)
  }
}

onMounted(reload)

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      loadBudget(id)
    } else {
      budget.value = null
    }
  },
)

// ── Computed helpers ────────────────────────────────────────────

const isEmpty = computed(
  () =>
    budget.value !== null &&
    budget.value.total_cost_usd === 0 &&
    budget.value.by_soul.length === 0,
)

// gateway returns daily DESC (max 30) — flip to ASC for the chart
const dailyBars = computed<BarDatum[]>(() =>
  [...(budget.value?.daily ?? [])]
    .sort((a, b) => a.date.localeCompare(b.date))
    .map((d) => ({ label: fmtDate(d.date), value: d.cost_usd })),
)

// threshold: pro-rated daily budget pace (limit / 30 days)
const dailyThreshold = computed(() => {
  const limit = budget.value?.budget_limit_usd
  return limit && limit > 0 ? limit / 30 : undefined
})

const soulsSorted = computed(() =>
  [...(budget.value?.by_soul ?? [])].sort((a, b) => b.cost_usd - a.cost_usd),
)

const maxSoulCost = computed(() =>
  Math.max(...soulsSorted.value.map((s) => s.cost_usd), 0.0001),
)

// ── Formatters ──────────────────────────────────────────────────

function fmtDate(dateStr: string): string {
  const d = new Date(dateStr)
  if (isNaN(d.getTime())) return dateStr
  return `${d.getMonth() + 1}/${d.getDate()}`
}
</script>

<template>
  <div class="usage-view">
    <header class="page-header">
      <div class="header-left">
        <h2 class="header-title">{{ t('usage.costTitle') }}</h2>
        <span v-if="profilesStore.activeProfile" class="header-project">
          {{ profilesStore.activeProfile.name }}
        </span>
      </div>
      <NButton
        size="small"
        quaternary
        :loading="loading"
        :disabled="!profilesStore.activeProfile"
        @click="reload"
      >
        {{ t('usage.refresh') }}
      </NButton>
    </header>

    <div class="usage-content">
      <!-- No project selected -->
      <EmptyState
        v-if="!profilesStore.activeProfile"
        :title="t('usage.noProject')"
      />

      <!-- Loading skeleton -->
      <template v-else-if="loading">
        <div class="summary-skeleton">
          <SkeletonCard v-for="i in 4" :key="i" :rows="2" />
        </div>
        <div class="two-col">
          <SkeletonCard :rows="5" />
          <SkeletonCard :rows="5" />
        </div>
      </template>

      <!-- Error -->
      <EmptyState
        v-else-if="error"
        :title="t('usage.loadFailed')"
        :action="{ label: t('common.retry'), handler: reload }"
      />

      <!-- No cost data -->
      <EmptyState
        v-else-if="isEmpty"
        :title="t('usage.noCostData')"
        :description="t('usage.noCostDataHint')"
      />

      <!-- Main content -->
      <template v-else-if="budget">
        <NAlert
          v-if="budget.warning"
          type="warning"
          :title="budget.warning"
          class="warning-alert"
          closable
        />

        <BudgetSummaryCards :budget="budget" />

        <div class="two-col">
          <!-- Daily cost trend -->
          <div class="panel">
            <h3 class="panel-title">{{ t('usage.dailyCostTrend') }}</h3>
            <MiniBarChart
              :data="dailyBars"
              :threshold="dailyThreshold"
              :height="140"
            />
            <p v-if="dailyThreshold" class="panel-hint">
              {{ t('usage.dailyPace', { amount: fmtUsd(dailyThreshold) }) }}
            </p>
          </div>

          <!-- Cost by SOUL -->
          <div class="panel">
            <h3 class="panel-title">{{ t('usage.soulBreakdown') }}</h3>
            <div class="soul-list">
              <div v-for="s in soulsSorted" :key="s.soul" class="soul-row">
                <span class="soul-name">{{ s.soul }}</span>
                <div class="soul-bar-wrap">
                  <div
                    class="soul-bar"
                    :style="{ width: (s.cost_usd / maxSoulCost * 100) + '%' }"
                  />
                </div>
                <span class="soul-cost">{{ fmtUsd(s.cost_usd) }}</span>
                <span class="soul-tasks">{{ s.tasks }}{{ t('usage.taskSuffix') }}</span>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.usage-view {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
  gap: 12px;
}

.header-left {
  display: flex;
  align-items: baseline;
  gap: 10px;
  min-width: 0;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
  flex-shrink: 0;
}

.header-project {
  font-size: 13px;
  color: $text-muted;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.usage-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  max-width: 960px;
  margin: 0 auto;
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 20px;
  scrollbar-width: none;
  -ms-overflow-style: none;

  &::-webkit-scrollbar {
    display: none;
  }
}

.warning-alert {
  flex-shrink: 0;
}

.summary-skeleton {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;

  @media (max-width: 768px) {
    grid-template-columns: repeat(2, 1fr);
  }
}

// ── Two-column grid ─────────────────────────────────────────────

.two-col {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;

  @media (max-width: 768px) {
    grid-template-columns: 1fr;
  }
}

.panel {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px;
  min-width: 0;
  box-shadow: var(--shadow-sm);
}

.panel-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-secondary;
  margin: 0 0 12px;
}

.panel-hint {
  font-size: 11px;
  color: $text-muted;
  margin: 8px 0 0;
}

// ── Soul breakdown ──────────────────────────────────────────────

.soul-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.soul-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.soul-name {
  font-size: 12px;
  font-family: $font-code;
  color: $text-secondary;
  width: 80px;
  flex-shrink: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.soul-bar-wrap {
  flex: 1;
  height: 14px;
  background: $bg-secondary;
  border-radius: 3px;
  overflow: hidden;
}

.soul-bar {
  height: 100%;
  background: rgba(var(--accent-primary-rgb), 0.75);
  border-radius: 3px;
  min-width: 2px;
  transition: width 0.3s var(--ease-out);
}

.soul-cost {
  font-size: 12px;
  color: $text-primary;
  font-family: $font-code;
  width: 64px;
  text-align: right;
  flex-shrink: 0;
}

.soul-tasks {
  font-size: 11px;
  color: $text-muted;
  width: 40px;
  flex-shrink: 0;
}
</style>
