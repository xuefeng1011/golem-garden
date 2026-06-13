<script setup lang="ts">
/**
 * EditorToolbar — top bar for FlowEditorView.
 * Emits actions; parent owns all state.
 */
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { NInput, NButton, NIcon, NTooltip, NSelect } from 'naive-ui'
import {
  AddOutline,
  GitMergeOutline,
  CheckmarkCircleOutline,
  SaveOutline,
  PlayOutline,
  TrashOutline,
  EnterOutline,
  HardwareChipOutline,
} from '@vicons/ionicons5'
import type { Flow } from '@/api/hermes/flows'

const props = defineProps<{
  goal: string
  dirty: boolean
  saving: boolean
  hasFlowId: boolean
  running: boolean
  flows: Flow[]
  selectedFlowId: string | null
  doneCount: number
  totalCount: number
}>()

const emit = defineEmits<{
  (e: 'update:goal', val: string): void
  (e: 'add-step'): void
  (e: 'add-input'): void
  (e: 'add-agent'): void
  (e: 'auto-layout'): void
  (e: 'validate'): void
  (e: 'save'): void
  (e: 'run'): void
  (e: 'select-flow', flowId: string): void
  (e: 'new-flow'): void
  (e: 'delete-flow'): void
}>()

const { t } = useI18n()

const flowOptions = computed(() =>
  props.flows.map((f) => ({
    label: f.goal || t('flowEditor.defaultGoal'),
    value: f.flow_id,
  })),
)

const showProgress = computed(
  () => props.totalCount > 0 && (props.doneCount > 0 || props.running),
)
</script>

<template>
  <header class="editor-toolbar">
    <!-- Flow selector row -->
    <div class="flow-selector-row">
      <NSelect
        v-if="flows.length > 0"
        :value="selectedFlowId"
        :options="flowOptions"
        :placeholder="t('flowEditor.savedFlowsPlaceholder')"
        size="small"
        class="flow-select"
        clearable
        @update:value="(v: string | null) => { if (v) emit('select-flow', v) }"
      />
      <NButton size="small" secondary @click="emit('new-flow')">
        {{ t('flowEditor.newFlow') }}
      </NButton>
      <NTooltip v-if="hasFlowId" trigger="hover">
        <template #trigger>
          <NButton size="small" type="error" ghost @click="emit('delete-flow')">
            <template #icon><NIcon><TrashOutline /></NIcon></template>
          </NButton>
        </template>
        {{ t('flowEditor.deleteFlow') }}
      </NTooltip>
    </div>

    <!-- Workflow name -->
    <NInput
      :value="goal"
      :placeholder="t('flowEditor.goalPlaceholder')"
      size="small"
      class="goal-input"
      @update:value="emit('update:goal', $event)"
    />

    <div class="toolbar-actions">
      <!-- Progress count -->
      <span v-if="showProgress" class="progress-count">
        {{ t('flowEditor.progressCount', { done: doneCount, total: totalCount }) }}
      </span>

      <NTooltip trigger="hover">
        <template #trigger>
          <NButton size="small" @click="emit('add-input')">
            <template #icon><NIcon><EnterOutline /></NIcon></template>
            {{ t('flowEditor.btnAddInput') }}
          </NButton>
        </template>
        {{ t('flowEditor.btnAddInputTip') }}
      </NTooltip>

      <NTooltip trigger="hover">
        <template #trigger>
          <NButton size="small" @click="emit('add-agent')">
            <template #icon><NIcon><HardwareChipOutline /></NIcon></template>
            {{ t('flowEditor.btnAddAgent') }}
          </NButton>
        </template>
        {{ t('flowEditor.btnAddAgentTip') }}
      </NTooltip>

      <NTooltip trigger="hover">
        <template #trigger>
          <NButton size="small" @click="emit('auto-layout')">
            <template #icon><NIcon><GitMergeOutline /></NIcon></template>
            {{ t('flowEditor.btnAutoLayout') }}
          </NButton>
        </template>
        {{ t('flowEditor.btnAutoLayoutTip') }}
      </NTooltip>

      <NTooltip trigger="hover">
        <template #trigger>
          <NButton size="small" @click="emit('validate')">
            <template #icon><NIcon><CheckmarkCircleOutline /></NIcon></template>
            {{ t('flowEditor.btnValidate') }}
          </NButton>
        </template>
        {{ t('flowEditor.btnValidateTip') }}
      </NTooltip>

      <NButton
        size="small"
        type="primary"
        :loading="saving"
        @click="emit('save')"
      >
        <template #icon><NIcon><SaveOutline /></NIcon></template>
        {{ t('flowEditor.btnSave') }}
        <span v-if="dirty" class="dirty-dot" aria-hidden="true" />
      </NButton>

      <NButton
        size="small"
        type="info"
        :disabled="!hasFlowId || running"
        :loading="running"
        @click="emit('run')"
      >
        <template #icon><NIcon><PlayOutline /></NIcon></template>
        {{ t('flowEditor.btnRun') }}
      </NButton>
    </div>
  </header>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.editor-toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-bottom: 1px solid $border-color;
  background: $bg-card;
  flex-shrink: 0;
  flex-wrap: wrap;
}

.flow-selector-row {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.flow-select {
  width: 200px;
}

.goal-input {
  flex: 1;
  min-width: 180px;
  max-width: 360px;
}

.toolbar-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.dirty-dot {
  display: inline-block;
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: $warning;
  margin-left: 4px;
  vertical-align: middle;
}

.progress-count {
  font-size: 12px;
  font-weight: 600;
  color: $accent-primary;
  padding: 2px 8px;
  background: rgba(var(--accent-primary-rgb), 0.1);
  border-radius: 10px;
  white-space: nowrap;
}
</style>
