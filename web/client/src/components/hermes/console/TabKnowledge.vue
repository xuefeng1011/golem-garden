<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { aggregateKnowledge, type KnowledgeRef } from '@/utils/trace'

const { t } = useI18n()

const props = defineProps<{
  lines: object[]
}>()

const refs = computed<KnowledgeRef[]>(() => aggregateKnowledge(props.lines))
</script>

<template>
  <div class="knowledge-root">
    <div class="knowledge-table-wrap">
      <table class="knowledge-table">
        <thead>
          <tr>
            <th>{{ t('console.colRef') }}</th>
            <th>{{ t('console.colCount') }}</th>
            <th>{{ t('console.colTools') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="ref in refs" :key="ref.ref" class="ref-row">
            <td class="cell-ref">{{ ref.ref }}</td>
            <td class="cell-count">{{ ref.count }}</td>
            <td class="cell-tools">
              <span
                v-for="tool in ref.tools"
                :key="tool"
                class="tool-tag"
              >{{ tool }}</span>
            </td>
          </tr>
          <tr v-if="refs.length === 0">
            <td colspan="3" class="empty-row">{{ t('common.noData') }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.knowledge-root {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.knowledge-table-wrap {
  flex: 1;
  overflow: auto;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  background: $bg-card;
}

.knowledge-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;

  th {
    padding: 9px 12px;
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

.ref-row {
  td {
    padding: 8px 12px;
    border-bottom: 1px solid $border-light;
    vertical-align: middle;
  }

  &:last-child td { border-bottom: none; }
}

.cell-ref {
  font-size: 12px;
  font-family: $font-code;
  color: $text-primary;
  max-width: 300px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cell-count {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  color: $text-primary;
  text-align: right;
  white-space: nowrap;
}

.cell-tools {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

.tool-tag {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  background: rgba(var(--accent-primary-rgb), 0.1);
  color: $accent-primary;
  white-space: nowrap;
}

.empty-row {
  text-align: center;
  color: $text-muted;
  padding: 24px !important;
}
</style>
