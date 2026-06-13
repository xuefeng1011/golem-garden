<script setup lang="ts">
/**
 * RunInputModal — prompt for input-node values right before a flow runs.
 *
 * Shown when the flow has one or more input nodes. Each input node gets a
 * textarea pre-filled with its current stored value; on confirm the parent
 * writes the edited values back into the nodes, saves, then runs.
 */
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { NModal, NCard, NInput, NButton, NFormItem } from 'naive-ui'

export interface RunInputField {
  nodeId: string
  stepId: string
  label: string
  value: string
}

const props = defineProps<{
  show: boolean
  fields: RunInputField[]
}>()

const emit = defineEmits<{
  (e: 'update:show', val: boolean): void
  (e: 'confirm', values: Record<string, string>): void
  (e: 'cancel'): void
}>()

const { t } = useI18n()

// 로컬 편집 상태 — nodeId -> 값
const local = ref<Record<string, string>>({})

watch(
  () => props.show,
  (open) => {
    if (open) {
      const next: Record<string, string> = {}
      for (const f of props.fields) next[f.nodeId] = f.value
      local.value = next
    }
  },
  { immediate: true },
)

function onConfirm() {
  emit('confirm', { ...local.value })
  emit('update:show', false)
}

function onCancel() {
  emit('cancel')
  emit('update:show', false)
}
</script>

<template>
  <NModal
    :show="show"
    @update:show="(v: boolean) => emit('update:show', v)"
    @mask-click="onCancel"
  >
    <NCard
      class="run-input-card"
      :title="t('flowEditor.runInputTitle')"
      :bordered="false"
      size="small"
      role="dialog"
      aria-modal="true"
    >
      <p class="run-input-desc">{{ t('flowEditor.runInputDesc') }}</p>

      <NFormItem
        v-for="f in fields"
        :key="f.nodeId"
        :label="f.label || f.stepId"
        label-placement="top"
      >
        <NInput
          v-model:value="local[f.nodeId]"
          type="textarea"
          :rows="3"
          :placeholder="t('flowEditor.inputValuePlaceholder')"
        />
      </NFormItem>

      <template #footer>
        <div class="run-input-actions">
          <NButton size="small" @click="onCancel">
            {{ t('common.cancel') }}
          </NButton>
          <NButton size="small" type="primary" @click="onConfirm">
            {{ t('flowEditor.runInputConfirm') }}
          </NButton>
        </div>
      </template>
    </NCard>
  </NModal>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.run-input-card {
  width: 440px;
  max-width: 92vw;
}

.run-input-desc {
  margin: 0 0 12px;
  font-size: 13px;
  color: $text-muted;
  line-height: 1.5;
}

.run-input-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
