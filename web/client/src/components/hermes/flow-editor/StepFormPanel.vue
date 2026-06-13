<script setup lang="ts">
/**
 * StepFormPanel — right-side panel shown when an editor node is selected.
 * Emits update events; parent replaces node.data (shallowRef — G7).
 */
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  NForm,
  NFormItem,
  NInput,
  NInputNumber,
  NSelect,
  NSwitch,
  NIcon,
} from 'naive-ui'
import { CloseOutline } from '@vicons/ionicons5'
import type { EditorNodeData } from '@/utils/canvas-graph'
import type { Soul } from '@/api/hermes/souls'

const props = defineProps<{
  data: EditorNodeData
  souls: Soul[]
  allStepOptions: { label: string; value: string }[]
}>()

const emit = defineEmits<{
  (e: 'update', patch: Partial<EditorNodeData>): void
  (e: 'close'): void
  (e: 'delete'): void
  (e: 'view-result', runId: string): void
}>()

const { t } = useI18n()

// soul options: empty = host
const soulOptions = computed(() => [
  { label: t('flowEditor.soulHost'), value: '' },
  ...props.souls.map((s) => ({ label: s.name, value: s.id })),
])

const onFailOptions = computed(() => [
  { label: t('flowEditor.onFailAbort'), value: 'abort' },
  { label: t('flowEditor.onFailContinue'), value: 'continue' },
  { label: t('flowEditor.onFailGoto'), value: '__goto__' },
])

// Derive whether current on_fail is a goto
const isGoto = computed(() => props.data.on_fail?.startsWith('goto:'))
const gotoTarget = computed(() =>
  isGoto.value ? props.data.on_fail.slice('goto:'.length) : '',
)

const onFailSelectValue = computed(() =>
  isGoto.value ? '__goto__' : (props.data.on_fail ?? 'abort'),
)

// goto step options: all steps except self
const gotoOptions = computed(() =>
  props.allStepOptions.filter((opt) => opt.value !== props.data.stepId),
)

function onSoulChange(val: string) {
  emit('update', { soul: val })
}

function onTaskChange(val: string) {
  emit('update', {
    task: val,
    label: val.length > 40 ? val.slice(0, 37) + '…' : val,
  })
}

function onRetryChange(val: number | null) {
  emit('update', { retry: val ?? 0 })
}

function onApprovalChange(val: boolean) {
  emit('update', { approval: val })
}

function onOnFailChange(val: string) {
  if (val === '__goto__') {
    emit('update', { on_fail: 'goto:' })
  } else {
    emit('update', { on_fail: val })
  }
}

function onGotoTargetChange(val: string) {
  emit('update', { on_fail: `goto:${val}` })
}
</script>

<template>
  <aside class="step-form-panel">
    <header class="panel-header">
      <span class="panel-title">{{ t('flowEditor.stepDetail') }}</span>
      <button class="close-btn" :title="t('common.cancel')" @click="emit('close')">
        <NIcon :size="16"><CloseOutline /></NIcon>
      </button>
    </header>

    <NForm label-placement="top" class="panel-form" size="small">
      <!-- SOUL -->
      <NFormItem :label="t('flowEditor.labelSoul')">
        <NSelect
          :value="data.soul"
          :options="soulOptions"
          :placeholder="t('flowEditor.soulHost')"
          clearable
          @update:value="onSoulChange"
        />
      </NFormItem>

      <!-- Task content -->
      <NFormItem :label="t('flowEditor.labelTask')" :feedback="data.hasError ? t('flowEditor.taskRequired') : undefined" :validation-status="data.hasError ? 'error' : undefined">
        <NInput
          :value="data.task"
          type="textarea"
          :rows="3"
          :placeholder="t('flowEditor.taskPlaceholder')"
          @update:value="onTaskChange"
        />
      </NFormItem>

      <!-- Retry -->
      <NFormItem :label="t('flowEditor.labelRetry')">
        <NInputNumber
          :value="data.retry ?? 1"
          :min="0"
          :max="3"
          @update:value="onRetryChange"
        />
      </NFormItem>

      <!-- Approval gate -->
      <NFormItem :label="t('flowEditor.labelApproval')">
        <NSwitch
          :value="data.approval"
          @update:value="onApprovalChange"
        />
      </NFormItem>

      <!-- On fail -->
      <NFormItem :label="t('flowEditor.labelOnFail')">
        <NSelect
          :value="onFailSelectValue"
          :options="onFailOptions"
          @update:value="onOnFailChange"
        />
      </NFormItem>

      <!-- Goto target (only when on_fail is goto) -->
      <NFormItem v-if="isGoto" :label="t('flowEditor.labelGotoStep')">
        <NSelect
          :value="gotoTarget"
          :options="gotoOptions"
          :placeholder="t('flowEditor.gotoPlaceholder')"
          @update:value="onGotoTargetChange"
        />
      </NFormItem>
    </NForm>

    <!-- 액션 버튼 -->
    <div class="panel-actions">
      <button
        v-if="data.runId"
        class="action-btn action-btn--result"
        @click="emit('view-result', data.runId!)"
      >
        {{ t('flowEditor.btnViewResult') }}
      </button>
      <button
        class="action-btn action-btn--delete"
        @click="emit('delete')"
      >
        {{ t('flowEditor.btnDeleteStep') }}
      </button>
    </div>
  </aside>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.step-form-panel {
  position: absolute;
  top: 0;
  right: 0;
  width: 280px;
  height: 100%;
  background: $bg-card;
  border-left: 1px solid $border-color;
  display: flex;
  flex-direction: column;
  z-index: 10;
  overflow-y: auto;
}

.panel-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  border-bottom: 1px solid $border-color;
  flex-shrink: 0;
}

.panel-title {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
}

.close-btn {
  display: flex;
  align-items: center;
  background: none;
  border: none;
  cursor: pointer;
  color: $text-muted;
  padding: 2px;
  border-radius: $radius-sm;

  &:hover {
    color: $text-primary;
  }
}

.panel-form {
  padding: 14px;
  flex: 1;
}

.panel-actions {
  padding: 10px 14px 14px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  border-top: 1px solid $border-color;
  flex-shrink: 0;
}

.action-btn {
  width: 100%;
  padding: 7px 12px;
  border-radius: $radius-sm;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background $transition-fast, border-color $transition-fast, color $transition-fast;

  &--result {
    background: rgba(var(--accent-primary-rgb), 0.08);
    border-color: rgba(var(--accent-primary-rgb), 0.25);
    color: $accent-primary;

    &:hover {
      background: rgba(var(--accent-primary-rgb), 0.15);
      border-color: $accent-primary;
    }
  }

  &--delete {
    background: rgba(var(--error-rgb), 0.07);
    border-color: rgba(var(--error-rgb), 0.2);
    color: $error;

    &:hover {
      background: rgba(var(--error-rgb), 0.14);
      border-color: $error;
    }
  }
}
</style>
