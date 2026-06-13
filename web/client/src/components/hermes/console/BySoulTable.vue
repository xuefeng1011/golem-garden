<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { BySoulEntry } from '@/api/hermes/console'
import { fmtUsd } from '@/utils/format'

const { t } = useI18n()

defineProps<{
  entries: BySoulEntry[]
}>()

// success_rate는 서버가 0..1 비율로 보냄
function rateClass(rate: number): string {
  if (rate >= 0.7) return 'is-success'
  if (rate < 0.4) return 'is-warning'
  return ''
}
</script>

<template>
  <div class="by-soul-wrap">
    <div class="section-label">{{ t('console.bySoul') }}</div>
    <table class="by-soul-table">
      <thead>
        <tr>
          <th>{{ t('console.colSoul') }}</th>
          <th>{{ t('console.colRuns') }}</th>
          <th>{{ t('console.colSuccessRate') }}</th>
          <th>{{ t('console.colCost') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="entry in entries" :key="entry.soul" class="soul-row">
          <td class="cell-soul">{{ entry.soul }}</td>
          <td class="cell-num">{{ entry.runs }}</td>
          <td class="cell-num" :class="rateClass(entry.success_rate)">
            {{ (entry.success_rate * 100).toFixed(1) }}%
          </td>
          <td class="cell-num">{{ fmtUsd(entry.cost_usd) }}</td>
        </tr>
        <tr v-if="entries.length === 0">
          <td colspan="4" class="empty-row">{{ t('common.noData') }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.by-soul-wrap {
  margin-bottom: 20px;
}

.section-label {
  font-size: 11px;
  font-weight: 600;
  color: $text-muted;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  margin-bottom: 8px;
}

.by-soul-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  overflow: hidden;
  background: $bg-card;

  th {
    padding: 8px 12px;
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

.soul-row {
  td {
    padding: 7px 12px;
    border-bottom: 1px solid $border-light;
    color: $text-secondary;
  }

  &:last-child td { border-bottom: none; }
}

.cell-soul {
  font-weight: 600;
  color: $text-primary !important;
}

.cell-num {
  font-variant-numeric: tabular-nums;
  text-align: right;

  &.is-success { color: $success !important; }
  &.is-warning { color: $warning !important; }
}

.empty-row {
  text-align: center;
  color: $text-muted;
  padding: 20px !important;
}
</style>
