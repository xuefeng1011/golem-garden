<script setup lang="ts">
import { NTag } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import type { ActivityEntry } from '@/api/hermes/overview'

const { t } = useI18n()

defineProps<{ activities: ActivityEntry[] }>()

function formatDate(ts: string): string {
  if (!ts) return ''
  // ts may be YYYY-MM-DD or ISO
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ts
  const month = d.getMonth() + 1
  const day = d.getDate()
  return `${month}월 ${day}일`
}

function truncateTask(task: string, max = 60): string {
  if (!task) return ''
  return task.length > max ? task.slice(0, max) + '…' : task
}

function resultType(result: string): 'success' | 'error' | 'warning' | 'default' {
  if (!result) return 'default'
  const r = result.toLowerCase()
  if (r === 'success' || r === '성공') return 'success'
  if (r === 'error' || r === 'fail' || r === 'failed' || r === '실패') return 'error'
  if (r === 'partial' || r === 'warning') return 'warning'
  return 'default'
}
</script>

<template>
  <div class="activity-wrap">
    <h3 class="section-title">{{ t('overview.activityTitle') }}</h3>
    <div v-if="activities.length === 0" class="empty-state">
      {{ t('overview.activityEmpty') }}
    </div>
    <div v-else class="activity-list">
      <div
        v-for="(entry, idx) in activities.slice(0, 8)"
        :key="idx"
        class="activity-item"
      >
        <div class="activity-header">
          <span class="soul-name">{{ entry.soul }}</span>
          <NTag
            size="small"
            :bordered="false"
            :type="resultType(entry.result)"
            class="result-tag"
          >
            {{ entry.result || t('overview.resultUnknown') }}
          </NTag>
        </div>
        <div class="activity-task">{{ truncateTask(entry.task) }}</div>
        <div class="activity-ts">{{ formatDate(entry.ts) }}</div>
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
}

.activity-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}

.soul-name {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
}

.result-tag {
  font-size: 11px;
  flex-shrink: 0;
}

.activity-task {
  font-size: 12px;
  color: $text-secondary;
  line-height: 1.4;
  margin-bottom: 4px;
}

.activity-ts {
  font-size: 11px;
  color: $text-muted;
}

.empty-state {
  padding: 40px 0;
  text-align: center;
  color: $text-muted;
  font-size: 13px;
}
</style>
