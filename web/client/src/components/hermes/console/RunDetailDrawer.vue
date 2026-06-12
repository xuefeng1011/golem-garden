<script setup lang="ts">
import { computed } from 'vue'
import { NDrawer, NDrawerContent, NTabs, NTab, NSpin, NButton, NIcon } from 'naive-ui'
import { AlertCircleOutline, ChevronDownOutline } from '@vicons/ionicons5'
import { useI18n } from 'vue-i18n'
import type { RunMeta } from '@/api/hermes/console'
import type { TraceResponse } from '@/api/hermes/traces'
import { fmtUsd } from '@/utils/format'
import TabReplay from './TabReplay.vue'
import TabTools from './TabTools.vue'
import TabReasoning from './TabReasoning.vue'
import TabKnowledge from './TabKnowledge.vue'

const { t } = useI18n()

const props = defineProps<{
  show: boolean
  run: RunMeta | null
  traceData: TraceResponse | null
  traceLoading: boolean
  traceError: { message: string } | null
  traceAppending: boolean
  projectId: string
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'loadMore'): void
}>()

const lines = computed(() => props.traceData?.lines ?? [])

const hasMore = computed(() => {
  if (!props.traceData) return false
  return props.traceData.offset + props.traceData.lines.length < props.traceData.total_lines
})

function fmtDuration(ms: number): string {
  const sec = ms / 1000
  if (sec < 60) return sec.toFixed(1) + 's'
  return (sec / 60).toFixed(1) + 'm'
}
</script>

<template>
  <NDrawer
    :show="show"
    :width="680"
    placement="right"
    @update:show="(v) => { if (!v) emit('close') }"
  >
    <NDrawerContent
      :title="run ? `${run.soul} — ${run.run_id.slice(0, 8)}` : ''"
      closable
    >
      <!-- Run meta header -->
      <div v-if="run" class="run-meta">
        <span class="meta-item">
          <span class="meta-key">{{ t('console.colModel') }}:</span>
          {{ run.model }}
        </span>
        <span class="meta-item">
          <span class="meta-key">{{ t('console.colDuration') }}:</span>
          {{ fmtDuration(run.duration_ms) }}
        </span>
        <span class="meta-item">
          <span class="meta-key">{{ t('console.colCost') }}:</span>
          {{ fmtUsd(run.cost_usd) }}
        </span>
        <span class="meta-item">
          <span
            class="result-tag"
            :class="{
              'tag-success': run.result === 'success',
              'tag-error': run.result === 'error',
              'tag-timeout': run.result === 'timeout',
            }"
          >{{ run.result }}</span>
        </span>
      </div>

      <!-- Loading state -->
      <div v-if="traceLoading" class="center-spinner">
        <NSpin size="medium" />
        <span class="spinner-label">{{ t('common.loading') }}</span>
      </div>

      <!-- Error state -->
      <div v-else-if="traceError" class="error-state">
        <NIcon size="24" color="var(--error)"><AlertCircleOutline /></NIcon>
        <span class="error-msg">{{ traceError.message }}</span>
      </div>

      <!-- Tabs -->
      <NTabs v-else-if="traceData" type="line" animated class="trace-tabs">
        <NTab :name="'replay'" :tab="t('console.tabReplay')">
          <TabReplay :lines="lines" />
        </NTab>
        <NTab :name="'tools'" :tab="t('console.tabTools')">
          <TabTools :lines="lines" />
        </NTab>
        <NTab :name="'reasoning'" :tab="t('console.tabReasoning')">
          <TabReasoning :lines="lines" />
        </NTab>
        <NTab :name="'knowledge'" :tab="t('console.tabKnowledge')">
          <TabKnowledge :lines="lines" />
        </NTab>
      </NTabs>

      <!-- Load more -->
      <div v-if="hasMore && !traceLoading" class="load-more-row">
        <NButton
          size="small"
          secondary
          :loading="traceAppending"
          @click="emit('loadMore')"
        >
          <template #icon>
            <NIcon><ChevronDownOutline /></NIcon>
          </template>
          {{ t('console.loadMoreLines', { loaded: traceData?.lines.length, total: traceData?.total_lines }) }}
        </NButton>
      </div>
    </NDrawerContent>
  </NDrawer>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.run-meta {
  display: flex;
  gap: 14px;
  flex-wrap: wrap;
  padding: 8px 0 14px;
  border-bottom: 1px solid $border-color;
  margin-bottom: 12px;
  font-size: 13px;
}

.meta-key {
  font-weight: 600;
  color: $text-muted;
  margin-right: 4px;
}

.meta-item {
  color: $text-secondary;
}

.result-tag {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;

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

.center-spinner {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 40px;
}

.spinner-label {
  font-size: 13px;
  color: $text-muted;
}

.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 40px;
  color: $error;
  font-size: 13px;
}

.error-msg {
  color: $text-secondary;
  text-align: center;
}

.trace-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;

  :deep(.n-tab-pane) {
    height: calc(100vh - 280px);
    overflow-y: auto;
  }
}

.load-more-row {
  display: flex;
  justify-content: center;
  padding: 12px 0;
}
</style>
