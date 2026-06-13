<script setup lang="ts">
/**
 * EditorToolbar — top bar for FlowEditorView.
 * Emits actions; parent owns all state.
 */
import { useI18n } from 'vue-i18n'
import { NInput, NButton, NIcon, NTooltip } from 'naive-ui'
import {
  AddOutline,
  GitMergeOutline,
  CheckmarkCircleOutline,
  SaveOutline,
  PlayOutline,
} from '@vicons/ionicons5'

const props = defineProps<{
  goal: string
  dirty: boolean
  saving: boolean
  hasFlowId: boolean
  running: boolean
}>()

const emit = defineEmits<{
  (e: 'update:goal', val: string): void
  (e: 'add-step'): void
  (e: 'auto-layout'): void
  (e: 'validate'): void
  (e: 'save'): void
  (e: 'run'): void
}>()

const { t } = useI18n()
</script>

<template>
  <header class="editor-toolbar">
    <!-- Workflow name -->
    <NInput
      :value="goal"
      :placeholder="t('flowEditor.goalPlaceholder')"
      size="small"
      class="goal-input"
      @update:value="emit('update:goal', $event)"
    />

    <div class="toolbar-actions">
      <NTooltip trigger="hover">
        <template #trigger>
          <NButton size="small" @click="emit('add-step')">
            <template #icon><NIcon><AddOutline /></NIcon></template>
            {{ t('flowEditor.btnAddStep') }}
          </NButton>
        </template>
        {{ t('flowEditor.btnAddStepTip') }}
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
</style>
