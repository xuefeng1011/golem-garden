<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { NSpin, NButton, NEmpty } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useProfilesStore } from '@/stores/hermes/profiles'
import { fetchTimeline } from '@/api/hermes/activity'
import type { TimelineEvent, TimelineEventType } from '@/api/hermes/activity'
import { fetchMailbox } from '@/api/hermes/souls'
import type { MailboxMessage } from '@/api/hermes/souls'
import TimelineItem from '@/components/hermes/activity/TimelineItem.vue'
import MailboxFeed from '@/components/hermes/activity/MailboxFeed.vue'

const { t } = useI18n()
const profilesStore = useProfilesStore()

// ── View mode: timeline | mailbox ────────────────────────────────────────────
type ViewMode = 'timeline' | 'mailbox'
const viewMode = ref<ViewMode>('timeline')

// ── Timeline ─────────────────────────────────────────────────────────────────
const events = ref<TimelineEvent[]>([])
const loading = ref(false)
const error = ref(false)

const ALL_TYPES: TimelineEventType[] = ['task', 'session_start', 'session_end', 'mailbox']
const activeTypes = ref<Set<TimelineEventType>>(new Set(ALL_TYPES))

const LIMIT_STEPS = [50, 100, 200]
const limitIndex = ref(0)
const canLoadMore = computed(() => limitIndex.value < LIMIT_STEPS.length - 1)

const filteredEvents = computed(() =>
  events.value.filter(e => activeTypes.value.has(e.type as TimelineEventType))
)

async function load(projectId: string) {
  loading.value = true
  error.value = false
  try {
    events.value = await fetchTimeline(projectId, LIMIT_STEPS[limitIndex.value])
  } catch {
    error.value = true
    events.value = []
  } finally {
    loading.value = false
  }
}

async function loadMore() {
  if (!canLoadMore.value || !profilesStore.activeProfile?.id) return
  limitIndex.value++
  await load(profilesStore.activeProfile.id)
}

async function refresh() {
  if (!profilesStore.activeProfile?.id) return
  limitIndex.value = 0
  await load(profilesStore.activeProfile.id)
  await loadMailbox(profilesStore.activeProfile.id)
}

function toggleType(type: TimelineEventType) {
  const next = new Set(activeTypes.value)
  if (next.has(type)) {
    if (next.size > 1) next.delete(type)
  } else {
    next.add(type)
  }
  activeTypes.value = next
}

function toggleAll() {
  if (activeTypes.value.size === ALL_TYPES.length) {
    activeTypes.value = new Set([ALL_TYPES[0]])
  } else {
    activeTypes.value = new Set(ALL_TYPES)
  }
}

const isAllActive = computed(() => activeTypes.value.size === ALL_TYPES.length)

const TYPE_LABELS: Record<TimelineEventType, string> = {
  task: 'task',
  session_start: 'session',
  session_end: 'session_end',
  mailbox: 'mailbox',
}

// ── Mailbox ───────────────────────────────────────────────────────────────────
const mailboxMessages = ref<MailboxMessage[]>([])
const mailboxLoading = ref(false)
const mailboxError = ref(false)

async function loadMailbox(projectId: string) {
  mailboxLoading.value = true
  mailboxError.value = false
  try {
    mailboxMessages.value = await fetchMailbox(projectId)
  } catch {
    mailboxError.value = true
    mailboxMessages.value = []
  } finally {
    mailboxLoading.value = false
  }
}

onMounted(() => {
  if (profilesStore.activeProfile?.id) {
    load(profilesStore.activeProfile.id)
    loadMailbox(profilesStore.activeProfile.id)
  }
})

watch(
  () => profilesStore.activeProfile?.id,
  (id) => {
    if (id) {
      limitIndex.value = 0
      load(id)
      loadMailbox(id)
    } else {
      events.value = []
      mailboxMessages.value = []
    }
  }
)
</script>

<template>
  <div class="activity-view">
    <header class="page-header">
      <div class="header-left">
        <h2 class="header-title">{{ t('activity.title') }}</h2>
        <span v-if="profilesStore.activeProfile" class="header-project">
          {{ profilesStore.activeProfile.name }}
        </span>
      </div>
      <div class="filter-row">
        <!-- View mode toggle -->
        <button
          class="filter-chip"
          :class="{ active: viewMode === 'timeline' }"
          @click="viewMode = 'timeline'"
        >{{ t('activity.viewTimeline') }}</button>
        <button
          class="filter-chip"
          :class="{ active: viewMode === 'mailbox' }"
          @click="viewMode = 'mailbox'"
        >{{ t('activity.viewMailbox') }}</button>

        <!-- Timeline type filters (shown only in timeline mode) -->
        <template v-if="viewMode === 'timeline'">
          <span class="filter-sep">|</span>
          <button
            class="filter-chip"
            :class="{ active: isAllActive }"
            @click="toggleAll"
          >{{ t('activity.filterAll') }}</button>
          <button
            v-for="type in ALL_TYPES"
            :key="type"
            class="filter-chip"
            :class="{ active: activeTypes.has(type) }"
            @click="toggleType(type)"
          >{{ TYPE_LABELS[type] }}</button>
        </template>

        <button class="refresh-btn" :disabled="loading || mailboxLoading" @click="refresh">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="23 4 23 10 17 10" />
            <polyline points="1 20 1 14 7 14" />
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
          </svg>
        </button>
      </div>
    </header>

    <div class="activity-content">
      <div v-if="!profilesStore.activeProfile" class="empty-state">
        {{ t('activity.noProject') }}
      </div>

      <!-- Timeline view -->
      <NSpin v-if="viewMode === 'timeline'" :show="loading">
        <div v-if="error" class="error-card">
          <p class="error-message">{{ t('activity.loadFailed') }}</p>
          <NButton size="small" @click="refresh">{{ t('common.retry') }}</NButton>
        </div>

        <template v-else>
          <NEmpty
            v-if="!loading && filteredEvents.length === 0"
            :description="t('activity.empty')"
            class="empty-block"
          />

          <div v-else class="timeline">
            <TimelineItem
              v-for="(event, idx) in filteredEvents"
              :key="idx"
              :event="event"
              :class="{ 'tl-last': idx === filteredEvents.length - 1 }"
            />
          </div>

          <div v-if="!loading && filteredEvents.length > 0" class="load-more-row">
            <NButton
              v-if="canLoadMore"
              size="small"
              @click="loadMore"
              :loading="loading"
            >{{ t('activity.loadMore') }}</NButton>
            <span v-else class="load-end">{{ t('activity.loadEnd') }}</span>
          </div>
        </template>
      </NSpin>

      <!-- Mailbox view -->
      <NSpin v-else-if="viewMode === 'mailbox'" :show="mailboxLoading">
        <div v-if="mailboxError" class="error-card">
          <p class="error-message">{{ t('activity.mailbox.loadFailed') }}</p>
          <NButton size="small" @click="profilesStore.activeProfile?.id && loadMailbox(profilesStore.activeProfile.id)">{{ t('common.retry') }}</NButton>
        </div>
        <MailboxFeed v-else :messages="mailboxMessages" />
      </NSpin>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.activity-view {
  height: calc(100 * var(--vh));
  display: flex;
  flex-direction: column;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 20px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
  flex-wrap: wrap;
  gap: 10px;
}

.header-left {
  display: flex;
  align-items: center;
  gap: 10px;
}

.header-title {
  font-size: 16px;
  font-weight: 600;
  color: $text-primary;
}

.header-project {
  font-size: 12px;
  color: $text-muted;
}

.filter-row {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.filter-chip {
  padding: 4px 10px;
  border-radius: 12px;
  border: 1px solid $border-color;
  background: none;
  font-size: 12px;
  color: $text-secondary;
  cursor: pointer;
  transition: all $transition-fast;

  &:hover {
    border-color: $accent-primary;
    color: $accent-primary;
  }

  &.active {
    background-color: rgba(var(--accent-primary-rgb), 0.12);
    border-color: $accent-primary;
    color: $accent-primary;
  }
}

.filter-sep {
  color: $border-color;
  font-size: 14px;
  user-select: none;
}

.refresh-btn {
  padding: 5px 8px;
  border-radius: $radius-sm;
  border: 1px solid $border-color;
  background: none;
  color: $text-secondary;
  cursor: pointer;
  display: flex;
  align-items: center;
  transition: all $transition-fast;

  &:hover {
    color: $accent-primary;
    border-color: $accent-primary;
  }

  &:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
}

.activity-content {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
}

.empty-state {
  padding: 60px 0;
  text-align: center;
  color: $text-muted;
  font-size: 14px;
}

.error-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 60px 0;
  text-align: center;
}

.error-message {
  font-size: 14px;
  color: $text-secondary;
}

.empty-block {
  padding: 60px 0;
}

.timeline {
  display: flex;
  flex-direction: column;
  padding-left: 4px;
}

.tl-last :deep(.tl-line) {
  display: none;
}

.load-more-row {
  display: flex;
  justify-content: center;
  padding: 16px 0 4px;
}

.load-end {
  font-size: 12px;
  color: $text-muted;
}
</style>
