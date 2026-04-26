<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { NSpin, NAlert, NButton, NEmpty } from 'naive-ui'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchBudget } from '@/api/hermes/budget'
import type { ProjectBudget } from '@/api/hermes/budget'

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

onMounted(() => {
  if (profilesStore.activeProfile?.id) {
    loadBudget(profilesStore.activeProfile.id)
  }
})

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

const totalTasks = computed(() =>
  budget.value?.by_soul.reduce((s, r) => s + r.tasks, 0) ?? 0
)

const avgCostPerTask = computed(() => {
  if (!budget.value || totalTasks.value === 0) return 0
  return budget.value.total_cost_usd / totalTasks.value
})

const activeSouls = computed(() => budget.value?.by_soul.length ?? 0)

const usagePercent = computed(() => {
  if (!budget.value?.budget_limit_usd) return null
  return (budget.value.total_cost_usd / budget.value.budget_limit_usd) * 100
})

const budgetBadge = computed(() => {
  if (!budget.value) return ''
  const used = fmtCost(budget.value.total_cost_usd)
  if (!budget.value.budget_limit_usd) return `사용 ${used} / 한도 미설정`
  const limit = fmtCost(budget.value.budget_limit_usd)
  const pct = usagePercent.value!.toFixed(1)
  return `사용 ${used} / 한도 ${limit} (${pct}%)`
})

// sorted souls descending by cost
const soulsSorted = computed(() =>
  [...(budget.value?.by_soul ?? [])].sort((a, b) => b.cost_usd - a.cost_usd)
)

const maxSoulCost = computed(() =>
  Math.max(...soulsSorted.value.map(s => s.cost_usd), 1)
)

// daily bars: last 30 days from the array
const dailyData = computed(() => budget.value?.daily.slice(-30) ?? [])

const maxDailyCost = computed(() =>
  Math.max(...dailyData.value.map(d => d.cost_usd), 1)
)

// ── Formatters ──────────────────────────────────────────────────

function fmtCost(n: number): string {
  return '$' + n.toFixed(3)
}

function fmtDate(dateStr: string): string {
  const d = new Date(dateStr)
  return `${d.getMonth() + 1}/${d.getDate()}`
}
</script>

<template>
  <div class="usage-view">
    <header class="page-header">
      <div class="header-left">
        <h2 class="header-title">비용 대시보드</h2>
        <span v-if="profilesStore.activeProfile" class="header-project">
          {{ profilesStore.activeProfile.name }}
        </span>
      </div>
      <div class="header-right">
        <span v-if="budget" class="budget-badge">{{ budgetBadge }}</span>
        <NButton
          size="small"
          quaternary
          :loading="loading"
          :disabled="!profilesStore.activeProfile"
          @click="profilesStore.activeProfile && loadBudget(profilesStore.activeProfile.id ?? '')"
        >
          새로고침
        </NButton>
      </div>
    </header>

    <div class="usage-content">
      <!-- No project -->
      <div v-if="!profilesStore.activeProfile" class="center-state">
        프로젝트를 선택하세요.
      </div>

      <NSpin v-else :show="loading">
        <!-- Warning banner -->
        <NAlert
          v-if="budget?.warning"
          type="warning"
          :title="budget.warning"
          style="margin-bottom: 16px;"
          closable
        />

        <!-- Error -->
        <div v-if="error" class="center-state">
          <p class="error-msg">데이터를 불러올 수 없습니다.</p>
          <NButton size="small" @click="loadBudget(profilesStore.activeProfile!.id ?? '')">
            재시도
          </NButton>
        </div>

        <!-- Empty -->
        <NEmpty
          v-else-if="!loading && budget && budget.total_cost_usd === 0"
          description="아직 비용 기록이 없습니다"
          style="padding: 60px 0;"
        />

        <!-- Main content -->
        <template v-else-if="!loading && budget && budget.total_cost_usd > 0">
          <!-- Stat cards -->
          <div class="stat-cards">
            <div class="stat-card">
              <div class="stat-label">총 비용</div>
              <div class="stat-value">{{ fmtCost(budget.total_cost_usd) }}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">총 태스크</div>
              <div class="stat-value">{{ totalTasks }}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">평균 비용/태스크</div>
              <div class="stat-value">{{ fmtCost(avgCostPerTask) }}</div>
            </div>
            <div class="stat-card">
              <div class="stat-label">활성 SOUL</div>
              <div class="stat-value">{{ activeSouls }}</div>
            </div>
          </div>

          <!-- Two-column grid -->
          <div class="two-col">
            <!-- Left: Daily trend -->
            <div class="panel">
              <h3 class="panel-title">일별 비용 추세 (최근 30일)</h3>
              <div class="bar-chart">
                <div
                  v-for="d in dailyData"
                  :key="d.date"
                  class="bar-col"
                  :title="`${fmtDate(d.date)}: ${fmtCost(d.cost_usd)}`"
                >
                  <div class="bar-track">
                    <div
                      class="bar-fill"
                      :style="{ height: (d.cost_usd / maxDailyCost * 100) + '%' }"
                    />
                  </div>
                </div>
              </div>
              <div class="bar-dates">
                <span>{{ dailyData[0] ? fmtDate(dailyData[0].date) : '' }}</span>
                <span>{{ dailyData[dailyData.length - 1] ? fmtDate(dailyData[dailyData.length - 1].date) : '' }}</span>
              </div>
            </div>

            <!-- Right: Soul breakdown -->
            <div class="panel">
              <h3 class="panel-title">SOUL 별 비용</h3>
              <div class="soul-list">
                <div v-for="s in soulsSorted" :key="s.soul" class="soul-row">
                  <span class="soul-name">{{ s.soul }}</span>
                  <div class="soul-bar-wrap">
                    <div
                      class="soul-bar"
                      :style="{ width: (s.cost_usd / maxSoulCost * 100) + '%' }"
                    />
                  </div>
                  <span class="soul-cost">{{ fmtCost(s.cost_usd) }}</span>
                  <span class="soul-tasks">({{ s.tasks }}건)</span>
                </div>
              </div>
            </div>
          </div>
        </template>
      </NSpin>
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

.header-right {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-shrink: 0;
}

.budget-badge {
  font-size: 12px;
  color: $text-secondary;
  background: $bg-secondary;
  border: 1px solid $border-color;
  border-radius: $radius-sm;
  padding: 3px 8px;
  white-space: nowrap;
}

.usage-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  max-width: 960px;
  margin: 0 auto;
  width: 100%;
  scrollbar-width: none;
  -ms-overflow-style: none;

  &::-webkit-scrollbar {
    display: none;
  }
}

.center-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
}

.error-msg {
  font-size: 14px;
  color: $text-secondary;
}

// ── Stat cards ──────────────────────────────────────────────────

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
}

.panel-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-secondary;
  margin: 0 0 12px;
}

// ── Daily bar chart ─────────────────────────────────────────────

.bar-chart {
  display: flex;
  gap: 2px;
  margin-bottom: 4px;
}

.bar-col {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  cursor: default;
}

.bar-track {
  width: 100%;
  height: 120px;
  background: $bg-secondary;
  border-radius: 2px 2px 0 0;
  display: flex;
  align-items: flex-end;
}

.bar-fill {
  width: 100%;
  background: $accent-primary;
  border-radius: 2px 2px 0 0;
  min-height: 0;
  transition: height 0.3s ease;
  opacity: 0.7;

  .dark & {
    background: #66bb6a;
    opacity: 0.85;
  }
}

.bar-dates {
  display: flex;
  justify-content: space-between;
  font-size: 10px;
  color: $text-muted;
  margin-top: 4px;
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
  background: $accent-primary;
  border-radius: 3px;
  min-width: 2px;
  transition: width 0.3s ease;
  opacity: 0.7;

  .dark & {
    background: #66bb6a;
    opacity: 0.85;
  }
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
  width: 36px;
  flex-shrink: 0;
}
</style>
