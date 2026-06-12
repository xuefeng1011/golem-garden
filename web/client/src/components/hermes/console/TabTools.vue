<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { pairToolCalls, type ToolCallPair } from '@/utils/trace'

const { t } = useI18n()

const props = defineProps<{
  lines: object[]
}>()

const allPairs = computed<ToolCallPair[]>(() => pairToolCalls(props.lines))

type FilterMode = 'all' | 'mcp'
const filter = ref<FilterMode>('all')

const pairs = computed(() =>
  filter.value === 'mcp'
    ? allPairs.value.filter(p => p.isMcp)
    : allPairs.value
)

const mcpCount = computed(() => allPairs.value.filter(p => p.isMcp).length)
</script>

<template>
  <div class="tools-root">
    <!-- Filter tabs -->
    <div class="filter-tabs">
      <button
        class="filter-tab"
        :class="{ active: filter === 'all' }"
        @click="filter = 'all'"
      >
        {{ t('console.filterAll') }} ({{ allPairs.length }})
      </button>
      <button
        class="filter-tab"
        :class="{ active: filter === 'mcp' }"
        @click="filter = 'mcp'"
      >
        MCP ({{ mcpCount }})
      </button>
    </div>

    <!-- Tools table -->
    <div class="tools-table-wrap">
      <table class="tools-table">
        <thead>
          <tr>
            <th>{{ t('console.colToolName') }}</th>
            <th>{{ t('console.colInput') }}</th>
            <th>{{ t('console.colResult') }}</th>
            <th>{{ t('console.colStatus') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="pair in pairs" :key="pair.id" class="tool-row">
            <td class="cell-name">
              <span class="tool-name">{{ pair.name }}</span>
              <span v-if="pair.isMcp" class="mcp-badge">MCP</span>
            </td>
            <td class="cell-summary">{{ pair.inputSummary || '—' }}</td>
            <td class="cell-summary">{{ pair.resultSummary || '—' }}</td>
            <td>
              <span class="status-tag" :class="pair.ok ? 'tag-ok' : 'tag-fail'">
                {{ pair.ok ? 'ok' : 'fail' }}
              </span>
            </td>
          </tr>
          <tr v-if="pairs.length === 0">
            <td colspan="4" class="empty-row">{{ t('common.noData') }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.tools-root {
  display: flex;
  flex-direction: column;
  gap: 12px;
  height: 100%;
}

.filter-tabs {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
}

.filter-tab {
  padding: 5px 14px;
  border-radius: $radius-sm;
  border: 1px solid $border-color;
  background: none;
  color: $text-muted;
  font-size: 12px;
  cursor: pointer;
  transition: all $transition-fast;

  &.active {
    background: rgba(var(--accent-primary-rgb), 0.12);
    color: $accent-primary;
    border-color: rgba(var(--accent-primary-rgb), 0.35);
  }
}

.tools-table-wrap {
  flex: 1;
  overflow: auto;
  border: 1px solid $border-color;
  border-radius: $radius-md;
  background: $bg-card;
}

.tools-table {
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

.tool-row {
  td {
    padding: 8px 12px;
    border-bottom: 1px solid $border-light;
    color: $text-secondary;
    vertical-align: top;
  }

  &:last-child td { border-bottom: none; }
}

.cell-name {
  display: flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
}

.tool-name {
  font-weight: 600;
  color: $text-primary;
  font-size: 12px;
  font-family: $font-code;
}

.mcp-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 700;
  background: rgba(var(--accent-info-rgb), 0.15);
  color: var(--accent-info);
  letter-spacing: 0.3px;
}

.cell-summary {
  font-size: 12px;
  color: $text-muted;
  max-width: 200px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.status-tag {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;

  &.tag-ok {
    background: rgba(var(--success-rgb), 0.12);
    color: $success;
  }
  &.tag-fail {
    background: rgba(var(--error-rgb), 0.12);
    color: $error;
  }
}

.empty-row {
  text-align: center;
  color: $text-muted;
  padding: 24px !important;
}
</style>
