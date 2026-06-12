<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import { NModal, NIcon } from 'naive-ui'
import { FolderOpenOutline, AlertCircleOutline } from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchOverview, fetchBoard } from '@/api/hermes/overview'
import type { ProjectOverview, ProjectBoard } from '@/api/hermes/overview'
import StatCards from '@/components/hermes/overview/StatCards.vue'
import TeamGrid from '@/components/hermes/overview/TeamGrid.vue'
import RecentActivity from '@/components/hermes/overview/RecentActivity.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import SkeletonCard from '@/components/common/SkeletonCard.vue'
import { ApiError, kindToI18nKey } from '@/utils/api-error'

const { t } = useI18n()
const router = useRouter()
const profilesStore = useProfilesStore()

const overview = ref<ProjectOverview | null>(null)
const board = ref<ProjectBoard | null>(null)
const loading = ref(false)
const loadError = ref<ApiError | null>(null)
const showDebtModal = ref(false)

const onRetry = () => {
  const id = profilesStore.activeProfile?.id
  if (!id) return
  loadData(id)
}

function goToProfiles() {
  router.push({ name: 'hermes.profiles' })
}

async function loadData(projectId: string) {
  loading.value = true
  loadError.value = null
  try {
    const [ov, bd] = await Promise.all([
      fetchOverview(projectId),
      fetchBoard(projectId),
    ])
    overview.value = ov
    board.value = bd
  } catch (e) {
    loadError.value = e instanceof ApiError ? e : new ApiError(String(e), null, 'client')
    overview.value = null
    board.value = null
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  if (profilesStore.activeProfile?.id) {
    loadData(profilesStore.activeProfile.id)
  }
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      loadData(id)
    } else {
      overview.value = null
      board.value = null
    }
  },
)
</script>

<template>
  <div class="overview-view">
    <header class="page-header">
      <h2 class="header-title">
        {{ profilesStore.activeProfile?.name ?? t('overview.title') }}
      </h2>
      <span v-if="profilesStore.activeProfile" class="header-hint">
        {{ t('overview.switchHint') }}
      </span>
    </header>

    <div class="overview-content">
      <!-- No project selected -->
      <EmptyState
        v-if="!profilesStore.activeProfile"
        :title="t('overview.noProject')"
        :description="t('overview.noProjectDescription')"
        :action="{ label: t('overview.selectProject'), handler: goToProfiles }"
      >
        <template #icon>
          <NIcon><FolderOpenOutline /></NIcon>
        </template>
      </EmptyState>

      <!-- Loading skeleton -->
      <template v-else-if="loading">
        <StatCards loading />
        <div class="two-col">
          <div class="col-left">
            <SkeletonCard :rows="6" show-avatar />
          </div>
          <div class="col-right">
            <SkeletonCard :rows="6" show-avatar />
          </div>
        </div>
      </template>

      <!-- Error state -->
      <EmptyState
        v-else-if="loadError"
        :title="t('overview.loadFailed')"
        :description="t(kindToI18nKey(loadError)) + (loadError.kind === 'network' ? '\n' + t('common.gatewayHint') : '')"
        :action="{ label: t('common.retry'), handler: onRetry }"
      >
        <template #icon>
          <NIcon><AlertCircleOutline /></NIcon>
        </template>
      </EmptyState>

      <template v-else-if="overview">
        <!-- Stat row -->
        <StatCards :overview="overview" />

        <!-- Two-column body -->
        <div class="two-col">
          <div class="col-left">
            <TeamGrid :team="board?.team ?? []" />
          </div>
          <div class="col-right">
            <RecentActivity :activities="overview.recent_activity ?? []" />
          </div>
        </div>

        <!-- Footer: tech debt -->
        <div v-if="board && board.tech_debt.length > 0" class="footer-bar">
          <button class="debt-link" @click="showDebtModal = true">
            {{ t('overview.techDebt', { count: board.tech_debt.length }) }}
          </button>
        </div>
      </template>
    </div>

    <!-- Tech debt modal -->
    <NModal
      v-model:show="showDebtModal"
      preset="dialog"
      :title="t('overview.techDebtTitle')"
      style="width: 480px;"
    >
      <ul class="debt-list">
        <li v-for="(item, idx) in board?.tech_debt ?? []" :key="idx" class="debt-item" :class="{ resolved: item.resolved }">
          <span v-if="item.resolved" class="check">✓</span>
          {{ item.text }}
        </li>
      </ul>
    </NModal>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.overview-view {
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

.overview-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

.two-col {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  margin-bottom: 16px;

  @media (max-width: 768px) {
    grid-template-columns: 1fr;
  }
}

.col-left,
.col-right {
  min-width: 0;
}

.footer-bar {
  border-top: 1px solid $border-color;
  padding-top: 12px;
}

.debt-link {
  background: none;
  border: none;
  cursor: pointer;
  font-size: 13px;
  color: $text-muted;
  padding: 0;
  transition: color $transition-fast;

  &:hover {
    color: $accent-primary;
  }
}

.debt-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.debt-item {
  font-size: 13px;
  color: $text-secondary;
  padding: 6px 0;
  border-bottom: 1px solid $border-color;

  &:last-child {
    border-bottom: none;
  }

  &::before {
    content: '• ';
    color: $text-muted;
  }

  &.resolved {
    text-decoration: line-through;
    opacity: 0.6;
  }
}

.check {
  color: #52a770;
  margin-right: 0.4em;
}
</style>
