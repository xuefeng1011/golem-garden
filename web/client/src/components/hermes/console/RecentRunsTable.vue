<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { RunMeta } from '@/api/hermes/console'
import { fmtUsd } from '@/utils/format'

const { t } = useI18n()

defineProps<{
  runs: RunMeta[]
}>()

const emit = defineEmits<{
  (e: 'select', run: RunMeta): void
}>()

function fmtDuration(ms: number): string {
  const sec = ms / 1000
  if (sec < 60) return sec.toFixed(1) + 's'
  return (sec / 60).toFixed(1) + 'm'
}

function fmtTime(ts: string): string {
  if (!ts) return '—'
  const d = new Date(ts)
  if (isNaN(d.getTime())) return ts
  const now = Date.now()
  const diffMs = now - d.getTime()
  const diffMin = Math.floor(diffMs / 60000)
  if (diffMin < 1) return t('overview.timeJustNow')
  if (diffMin < 60) return t('overview.timeMinutesAgo', { n: diffMin })
  const diffH = Math.floor(diffMin / 60)
  if (diffH < 24) return t('overview.timeHoursAgo', { n: diffH })
  return t('overview.timeDaysAgo', { n: Math.floor(diffH / 24) })
}

function resultClass(result: string): string {
  if (result === 'success') return 'tag-success'
  if (result === 'error') return 'tag-error'
  return 'tag-timeout'
}
</script>

<template>
  <div class="runs-table-wrap">
    <table class="runs-table">
      <thead>
        <tr>
          <th>{{ t('console.colSoul') }}</th>
          <th>{{ t('console.colModel') }}</th>
          <th>{{ t('console.colResult') }}</th>
          <th>{{ t('console.colDuration') }}</th>
          <th>{{ t('console.colTokens') }}</th>
          <th>{{ t('console.colCost') }}</th>
          <th>{{ t('console.colStarted') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="run in runs"
          :key="run.run_id"
          class="run-row"
          @click="emit('select', run)"
        >
          <td class="cell-soul">{{ run.soul }}</td>
          <td class="cell-model">{{ run.model }}</td>
          <td>
            <span class="result-tag" :class="resultClass(run.result)">
              {{ run.result }}
            </span>
          </td>
          <td class="cell-num">{{ fmtDuration(run.duration_ms) }}</td>
          <td class="cell-num">{{ (run.tokens_in + run.tokens_out).toLocaleString() }}</td>
          <td class="cell-num">{{ fmtUsd(run.cost_usd) }}</td>
          <td class="cell-time">{{ fmtTime(run.ts_start) }}</td>
        </tr>
        <tr v-if="runs.length === 0">
          <td colspan="7" class="empty-row">{{ t('common.noData') }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.runs-table-wrap {
  overflow-x: auto;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  background: $bg-card;
}

.runs-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;

  th {
    padding: 10px 12px;
    text-align: left;
    font-size: 11px;
    font-weight: 600;
    color: $text-muted;
    text-transform: uppercase;
    letter-spacing: 0.4px;
    border-bottom: 1px solid $border-color;
    white-space: nowrap;
  }
}

.run-row {
  cursor: pointer;
  transition: background $transition-fast;

  td {
    padding: 9px 12px;
    border-bottom: 1px solid $border-light;
    color: $text-secondary;
    white-space: nowrap;
  }

  &:last-child td { border-bottom: none; }

  &:hover td {
    background: rgba(var(--accent-primary-rgb), 0.04);
    color: $text-primary;
  }
}

.cell-soul {
  font-weight: 600;
  color: $text-primary !important;
}

.cell-model {
  font-size: 12px;
  max-width: 140px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.cell-num {
  font-variant-numeric: tabular-nums;
  text-align: right;
}

.cell-time {
  color: $text-muted !important;
  font-size: 12px;
}

.result-tag {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.3px;

  &.tag-success {
    background: rgba(var(--success-rgb), 0.12);
    color: $success;
  }
  &.tag-error {
    background: rgba(var(--error-rgb), 0.12);
    color: $error;
  }
  &.tag-timeout {
    background: rgba(var(--warning-rgb), 0.12);
    color: $warning;
  }
}

.empty-row {
  text-align: center;
  color: $text-muted;
  padding: 24px !important;
}
</style>
