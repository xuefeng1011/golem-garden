<script setup lang="ts">
import { onMounted, onUnmounted, watch } from 'vue'
import { NIcon } from 'naive-ui'
import { TerminalOutline, AlertCircleOutline, FolderOpenOutline } from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { useConsoleStore } from '@/stores/hermes/console'
import { useRouter } from 'vue-router'
import { kindToI18nKey } from '@/utils/api-error'
import EmptyState from '@/components/common/EmptyState.vue'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import ConsoleStatCards from '@/components/hermes/console/ConsoleStatCards.vue'
import ActiveRunsBanner from '@/components/hermes/console/ActiveRunsBanner.vue'
import BySoulTable from '@/components/hermes/console/BySoulTable.vue'
import RecentRunsTable from '@/components/hermes/console/RecentRunsTable.vue'
import RunDetailDrawer from '@/components/hermes/console/RunDetailDrawer.vue'
import type { RunMeta } from '@/api/hermes/console'

const { t } = useI18n()
const router = useRouter()
const profilesStore = useProfilesStore()
const consoleStore = useConsoleStore()

function startPollingIfReady(projectId: string | undefined) {
  if (projectId) {
    consoleStore.startPolling(projectId)
  }
}

onMounted(() => {
  startPollingIfReady(profilesStore.activeProfile?.id)
})

onUnmounted(() => {
  consoleStore.stopPolling()
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      consoleStore.stopPolling()
      consoleStore.startPolling(id)
    } else {
      consoleStore.stopPolling()
    }
  },
)

function onRunSelect(run: RunMeta) {
  const pid = profilesStore.activeProfile?.id
  if (!pid) return
  consoleStore.selectRun(run, pid)
}

function onLoadMore() {
  const pid = profilesStore.activeProfile?.id
  if (!pid) return
  consoleStore.loadMoreTrace(pid)
}

function goToProfiles() {
  router.push({ name: 'hermes.profiles' })
}

function onRetry() {
  const pid = profilesStore.activeProfile?.id
  if (pid) consoleStore.startPolling(pid)
}
</script>

<template>
  <div class="console-view">
    <header class="page-header">
      <h2 class="header-title">{{ t('console.title') }}</h2>
      <span v-if="profilesStore.activeProfile" class="header-hint">
        {{ profilesStore.activeProfile.name }} — {{ t('console.pollHint') }}
      </span>
    </header>

    <div class="console-content">
      <!-- No project selected -->
      <EmptyState
        v-if="!profilesStore.activeProfile"
        :title="t('console.noProject')"
        :description="t('console.noProjectDescription')"
        :action="{ label: t('console.selectProject'), handler: goToProfiles }"
      >
        <template #icon>
          <NIcon><FolderOpenOutline /></NIcon>
        </template>
      </EmptyState>

      <!-- Loading skeleton (first load only) -->
      <template v-else-if="consoleStore.loading && !consoleStore.data">
        <ConsoleStatCards loading />
        <SkeletonCard :rows="4" />
        <SkeletonCard :rows="6" />
      </template>

      <!-- Error state -->
      <EmptyState
        v-else-if="consoleStore.loadError && !consoleStore.data"
        :title="t('console.loadFailed')"
        :description="t(kindToI18nKey(consoleStore.loadError))"
        :action="{ label: t('common.retry'), handler: onRetry }"
      >
        <template #icon>
          <NIcon><AlertCircleOutline /></NIcon>
        </template>
      </EmptyState>

      <template v-else-if="consoleStore.data">
        <!-- Stat cards -->
        <ConsoleStatCards
          :stats="consoleStore.data.stats"
          :budget="consoleStore.data.budget"
        />

        <!-- Active runs (only when present) -->
        <ActiveRunsBanner
          v-if="consoleStore.data.active_runs.length > 0"
          :runs="consoleStore.data.active_runs"
        />

        <!-- By-soul breakdown -->
        <BySoulTable
          v-if="consoleStore.data.by_soul.length > 0"
          :entries="consoleStore.data.by_soul"
        />

        <!-- Recent runs table -->
        <div class="section-label">{{ t('console.recentRuns') }}</div>
        <RecentRunsTable
          :runs="consoleStore.data.recent_runs"
          @select="onRunSelect"
        />

        <!-- Empty state for zero runs -->
        <EmptyState
          v-if="consoleStore.data.recent_runs.length === 0"
          :title="t('console.noRuns')"
          :description="t('console.noRunsDescription')"
        >
          <template #icon>
            <NIcon><TerminalOutline /></NIcon>
          </template>
        </EmptyState>
      </template>
    </div>

    <!-- Run detail drawer -->
    <RunDetailDrawer
      :show="!!consoleStore.selectedRun"
      :run="consoleStore.selectedRun"
      :trace-data="consoleStore.traceData"
      :trace-loading="consoleStore.traceLoading"
      :trace-error="consoleStore.traceError"
      :trace-appending="consoleStore.traceAppending"
      :project-id="profilesStore.activeProfile?.id ?? ''"
      @close="consoleStore.closeRun()"
      @load-more="onLoadMore"
    />
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.console-view {
  height: calc(100 * var(--vh));
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
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
}

.header-hint {
  font-size: 12px;
  color: $text-muted;
}

.console-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 0;
}

.section-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  margin-bottom: 8px;
}
</style>
