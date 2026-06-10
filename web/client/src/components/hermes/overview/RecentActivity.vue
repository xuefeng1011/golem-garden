<script setup lang="ts">
import { NIcon } from 'naive-ui'
import { CheckmarkCircle, CloseCircle, InformationCircle, PulseOutline } from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import type { ActivityEntry } from '@/api/hermes/overview'
import EmptyState from '@/components/common/EmptyState.vue'

const { t, locale } = useI18n()

defineProps<{ activities: ActivityEntry[] }>()

function relativeTime(ts: string): string {
  if (!ts) return ''
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ts
  const diffMs = Date.now() - d.getTime()
  if (diffMs < 0) return d.toLocaleDateString(locale.value, { month: 'short', day: 'numeric' })
  const minutes = Math.floor(diffMs / 60000)
  if (minutes < 1) return t('overview.timeJustNow')
  if (minutes < 60) return t('overview.timeMinutesAgo', { n: minutes })
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return t('overview.timeHoursAgo', { n: hours })
  const days = Math.floor(hours / 24)
  if (days < 7) return t('overview.timeDaysAgo', { n: days })
  return d.toLocaleDateString(locale.value, { month: 'short', day: 'numeric' })
}

function truncateTask(task: string, max = 60): string {
  if (!task) return ''
  return task.length > max ? task.slice(0, max) + '…' : task
}

type ResultKind = 'success' | 'fail' | 'info'

function resultKind(result: string): ResultKind {
  if (!result) return 'info'
  const r = result.toLowerCase()
  if (r === 'success' || r === '성공') return 'success'
  if (r === 'error' || r === 'fail' || r === 'failed' || r === '실패') return 'fail'
  return 'info'
}
</script>

<template>
  <div class="activity-wrap">
    <h3 class="section-title">{{ t('overview.activityTitle') }}</h3>
    <EmptyState
      v-if="activities.length === 0"
      :title="t('overview.activityEmpty')"
      :description="t('overview.activityEmptyDescription')"
    >
      <template #icon>
        <NIcon><PulseOutline /></NIcon>
      </template>
    </EmptyState>
    <div v-else class="activity-list">
      <div
        v-for="(entry, idx) in activities.slice(0, 8)"
        :key="idx"
        class="activity-item"
      >
        <div class="activity-header">
          <span
            class="result-icon"
            :class="`icon-${resultKind(entry.result)}`"
            :title="entry.result || t('overview.resultUnknown')"
          >
            <NIcon size="14">
              <CheckmarkCircle v-if="resultKind(entry.result) === 'success'" />
              <CloseCircle v-else-if="resultKind(entry.result) === 'fail'" />
              <InformationCircle v-else />
            </NIcon>
          </span>
          <span class="soul-name">{{ entry.soul }}</span>
          <span class="activity-ts">{{ relativeTime(entry.ts) }}</span>
        </div>
        <div class="activity-task">{{ truncateTask(entry.task) }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.activity-wrap {
  height: 100%;
}

.section-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin-bottom: 12px;
}

.activity-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.activity-item {
  background: $bg-card;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 10px 14px;
  transition: box-shadow 0.2s $ease-out;

  &:hover {
    box-shadow: $shadow-sm;
  }
}

.activity-header {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 4px;
}

.result-icon {
  flex-shrink: 0;
  display: flex;
  align-items: center;

  &.icon-success { color: $success; }
  &.icon-fail    { color: $error; }
  &.icon-info    { color: var(--accent-info); }
}

.soul-name {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.activity-ts {
  margin-left: auto;
  flex-shrink: 0;
  font-size: 11px;
  color: $text-muted;
}

.activity-task {
  font-size: 12px;
  color: $text-secondary;
  line-height: 1.4;
  padding-left: 20px;
}
</style>
