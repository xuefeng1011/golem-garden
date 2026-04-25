<script setup lang="ts">
import { ref, computed } from 'vue'
import { NButton, NTag, NSpin, NSkeleton, useMessage, useDialog } from 'naive-ui'
import type { HermesProfile, HermesProfileDetail } from '@/api/hermes/profiles'
import type { ProjectOverview, ActiveSoul } from '@/api/hermes/overview'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  profile: HermesProfile
  overview?: ProjectOverview | null
}>()
const emit = defineEmits<{}>()

const { t } = useI18n()
const profilesStore = useProfilesStore()
const message = useMessage()
const dialog = useDialog()

const expanded = ref(false)
const detailLoading = ref(false)
const exporting = ref(false)
const switching = ref(false)
const detail = ref<HermesProfileDetail | null>(null)

const isDefault = computed(() => props.profile.name === 'default')

// Overview-derived computeds
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000
const isRecentlyActive = computed(() => {
  if (!props.overview?.last_activity_ts) return false
  return Date.now() - new Date(props.overview.last_activity_ts).getTime() < SEVEN_DAYS_MS
})

const visibleSouls = computed<ActiveSoul[]>(() => {
  return (props.overview?.active_souls ?? []).slice(0, 3)
})

const extraSoulsCount = computed(() => {
  const total = props.overview?.active_souls?.length ?? 0
  return Math.max(0, total - 3)
})

function formatLastActivity(ts: string): string {
  if (!ts) return '—'
  const d = new Date(ts)
  const month = d.getMonth() + 1
  const day = d.getDate()
  return `${month}월 ${day}일`
}

const RANK_COLORS: Record<string, string> = {
  novice: '#888',
  junior: '#4a9eff',
  senior: '#52a770',
  master: '#a855f7',
}

async function toggleDetail() {
  if (expanded.value) {
    expanded.value = false
    return
  }
  expanded.value = true
  detailLoading.value = true
  try {
    detail.value = await profilesStore.fetchProfileDetail(props.profile.name)
  } finally {
    detailLoading.value = false
  }
}

async function handleSwitch() {
  switching.value = true
  try {
    const ok = await profilesStore.switchProfile(props.profile.name)
    if (ok) {
      window.location.reload()
    } else {
      message.error(t('profiles.switchFailed'))
    }
  } finally {
    switching.value = false
  }
}

function handleDelete() {
  dialog.warning({
    title: t('profiles.delete'),
    content: t('profiles.deleteConfirm', { name: props.profile.name }),
    positiveText: t('common.delete'),
    negativeText: t('common.cancel'),
    onPositiveClick: async () => {
      const ok = await profilesStore.deleteProfile(props.profile.name)
      if (ok) {
        message.success(t('profiles.deleteSuccess'))
      } else {
        message.error(t('profiles.deleteFailed'))
      }
    },
  })
}

async function handleExport() {
  exporting.value = true
  try {
    const ok = await profilesStore.exportProfile(props.profile.name)
    if (ok) {
      message.success(t('profiles.exportSuccess'))
    } else {
      message.error(t('profiles.exportFailed'))
    }
  } finally {
    exporting.value = false
  }
}
</script>

<template>
  <div class="profile-card" :class="{ active: profile.active }">
    <div class="card-header">
      <div class="header-left">
        <span
          class="activity-dot"
          :class="isRecentlyActive ? 'activity-dot--active' : 'activity-dot--idle'"
        />
        <h3 class="profile-name">{{ profile.name }}</h3>
      </div>
      <NTag v-if="profile.active" size="tiny" type="success" :bordered="false">
        {{ t('profiles.active') }}
      </NTag>
    </div>

    <!-- Overview enrichment block -->
    <div class="overview-block">
      <!-- Loading skeleton: profile has an id but overview not yet cached -->
      <template v-if="profile.id && overview === undefined">
        <NSkeleton text :repeat="1" style="width: 60%; height: 14px; margin-bottom: 8px;" />
        <div class="soul-badges-row">
          <NSkeleton v-for="n in 3" :key="n" style="width: 56px; height: 22px; border-radius: 4px;" />
        </div>
      </template>

      <!-- Loaded overview -->
      <template v-else-if="overview">
        <div class="overview-summary">
          <span>팀 {{ overview.souls_count }}명</span>
          <span class="sep">·</span>
          <span>태스크 {{ overview.total_tasks }}</span>
          <span class="sep">·</span>
          <span>마지막 {{ formatLastActivity(overview.last_activity_ts) }}</span>
        </div>
        <div class="soul-badges-row">
          <NTag
            v-for="soul in visibleSouls"
            :key="soul.id"
            size="tiny"
            :bordered="false"
            class="soul-badge"
            :style="{ color: RANK_COLORS[soul.rank] ?? '#888', backgroundColor: 'rgba(0,0,0,0.15)' }"
          >
            {{ soul.name }} {{ soul.rank }}
          </NTag>
          <span v-if="extraSoulsCount > 0" class="extra-souls">+{{ extraSoulsCount }}</span>
        </div>
      </template>
    </div>

    <div class="card-body">
      <div class="info-row">
        <span class="info-label">{{ t('profiles.model') }}</span>
        <code class="info-value mono">{{ profile.model }}</code>
      </div>
      <div class="info-row">
        <span class="info-label">{{ t('profiles.gateway') }}</span>
        <code class="info-value mono">{{ profile.gateway }}</code>
      </div>
    </div>

    <div class="card-detail-toggle" @click="toggleDetail">
      <svg
        width="14" height="14" viewBox="0 0 24 24" fill="none"
        stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
        class="toggle-icon"
        :class="{ expanded }"
      >
        <polyline points="6 9 12 15 18 9" />
      </svg>
      <span class="toggle-text">{{ expanded ? t('common.collapse') : t('common.expand') }}</span>
    </div>

    <div v-if="expanded" class="card-detail">
      <NSpin :show="detailLoading" size="small">
        <template v-if="detail">
          <div class="info-row">
            <span class="info-label">{{ t('profiles.provider') }}</span>
            <span class="info-value">{{ detail.provider }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">{{ t('profiles.path') }}</span>
            <code class="info-value mono detail-path">{{ detail.path }}</code>
          </div>
          <div class="info-row">
            <span class="info-label">{{ t('profiles.skills') }}</span>
            <span class="info-value">{{ detail.skills }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">{{ t('profiles.hasEnv') }}</span>
            <span class="info-value">{{ detail.hasEnv ? 'Yes' : 'No' }}</span>
          </div>
          <div class="info-row">
            <span class="info-label">{{ t('profiles.hasSoulMd') }}</span>
            <span class="info-value">{{ detail.hasSoulMd ? 'Yes' : 'No' }}</span>
          </div>
        </template>
      </NSpin>
    </div>

    <div class="card-actions">
      <NButton
        v-if="!profile.active"
        size="tiny"
        :loading="switching"
        quaternary
        type="primary"
        @click="handleSwitch"
      >
        {{ t('profiles.switchTo') }}
      </NButton>
      <NButton
        size="tiny"
        quaternary
        type="error"
        :disabled="isDefault || profile.active"
        @click="handleDelete"
      >
        {{ t('common.delete') }}
      </NButton>
      <NButton size="tiny" quaternary :loading="exporting" @click="handleExport">
        {{ t('profiles.export') }}
      </NButton>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.profile-card {
  background-color: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 16px;
  transition: border-color $transition-fast;

  &:hover {
    border-color: rgba(var(--accent-primary-rgb), 0.3);
  }

  &.active {
    border-color: rgba(var(--success-rgb), 0.4);
  }
}

.card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
}

.activity-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;

  &--active {
    background-color: #52a770;
    box-shadow: 0 0 4px #52a770;
  }

  &--idle {
    background-color: #666;
  }
}

.overview-block {
  margin-bottom: 8px;
  min-height: 44px;
}

.overview-summary {
  font-size: 12px;
  color: $text-muted;
  margin-bottom: 6px;
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
}

.sep {
  opacity: 0.5;
}

.soul-badges-row {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-wrap: wrap;
}

.soul-badge {
  font-size: 11px;
  height: 20px;
  line-height: 20px;
}

.extra-souls {
  font-size: 11px;
  color: $text-muted;
  padding: 0 4px;
}

.profile-name {
  font-size: 15px;
  font-weight: 600;
  color: $text-primary;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 70%;
}

.card-body {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 8px;
}

.card-detail-toggle {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 6px 0;
  cursor: pointer;
  color: $text-muted;
  font-size: 12px;
  user-select: none;

  &:hover {
    color: $text-secondary;
  }
}

.toggle-icon {
  transition: transform 0.2s;

  &.expanded {
    transform: rotate(180deg);
  }
}

.card-detail {
  padding: 8px 0;
  border-top: 1px solid $border-light;
  margin-bottom: 8px;
}

.info-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 2px 0;
}

.info-label {
  font-size: 12px;
  color: $text-muted;
  flex-shrink: 0;
  margin-right: 12px;
}

.info-value {
  font-size: 12px;
  color: $text-secondary;
  text-align: right;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mono {
  font-family: $font-code;
  font-size: 12px;
}

.detail-path {
  max-width: 260px;
}

.card-actions {
  display: flex;
  gap: 8px;
  border-top: 1px solid $border-light;
  padding-top: 10px;
  flex-wrap: wrap;
}
</style>
