<script setup lang="ts">
/**
 * StudioRedesignModal — 기존 스튜디오 팀/플로우를 피드백에 맞춰 재설계 (forge studio redesign).
 * flowsmith 를 재소환하므로 StudioCreateModal 의 design 스테이지와 동일한 SSE 스트리밍
 * 출력 패턴(StudioAgentModal output-panel)을 재사용한다. 완료 시 부모가 플로우 목록을
 * 재조회하고 새로 생성된(최신) 플로우를 선택하도록 'redesigned' 를 emit 한다.
 */
import { ref, computed, onUnmounted } from 'vue'
import { NModal, NForm, NFormItem, NInput, NButton, NAlert, NSpin } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import { validateForgeArg } from '@/utils/forge-args'

const props = defineProps<{
  show: boolean
  projectId: string
}>()

const emit = defineEmits<{
  'update:show': [boolean]
  redesigned: []
}>()

const { t } = useI18n()

const feedback = ref('')

const running = ref(false)
const output = ref<string[]>([])
const succeeded = ref(false)
const errorMsg = ref<string | null>(null)

let streamHandle: { abort: () => void } | null = null

const canSubmit = computed(() => !running.value && !succeeded.value)

function validate(): boolean {
  const trimmed = feedback.value.trim()
  if (!trimmed) {
    errorMsg.value = t('flowStudio.errors.feedbackRequired')
    return false
  }
  const err = validateForgeArg(trimmed)
  if (err) {
    errorMsg.value = t(`flowStudio.errors.${err}`)
    return false
  }
  errorMsg.value = null
  return true
}

async function handleRedesign() {
  if (!validate()) return

  running.value = true
  output.value = []
  succeeded.value = false

  try {
    const { run_id } = await startForge(props.projectId, 'studio', ['redesign', feedback.value.trim()])

    streamHandle = streamForgeEvents(
      run_id,
      (evt) => {
        if (evt.line !== undefined) output.value.push(evt.line)
      },
      (done) => {
        running.value = false
        streamHandle = null
        if ('exit_code' in done && done.exit_code === 0) {
          succeeded.value = true
          emit('redesigned')
        } else {
          errorMsg.value = t('flowStudio.redesignModal.failed')
        }
      },
      (err) => {
        running.value = false
        streamHandle = null
        errorMsg.value = err.message
      },
    )
  } catch (err) {
    running.value = false
    errorMsg.value = err instanceof Error ? err.message : String(err)
  }
}

function handleClose() {
  if (running.value) return
  streamHandle?.abort()
  streamHandle = null
  feedback.value = ''
  output.value = []
  succeeded.value = false
  errorMsg.value = null
  emit('update:show', false)
}

onUnmounted(() => {
  streamHandle?.abort()
  streamHandle = null
})
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    :title="t('flowStudio.redesignModal.title')"
    :style="{ width: 'min(480px, calc(100vw - 32px))' }"
    :mask-closable="!running"
    :close-on-esc="!running"
    @close="handleClose"
    @mask-click="handleClose"
  >
    <NForm label-placement="top" :disabled="!canSubmit">
      <NFormItem :label="t('flowStudio.redesignModal.feedbackLabel')" required>
        <NInput
          v-model:value="feedback"
          type="textarea"
          :placeholder="t('flowStudio.redesignModal.feedbackPlaceholder')"
          :autosize="{ minRows: 3, maxRows: 6 }"
        />
      </NFormItem>
    </NForm>

    <div v-if="output.length > 0 || running" class="output-panel">
      <NSpin :show="running" size="small">
        <div class="output-lines">
          <div v-for="(line, i) in output" :key="i" class="output-line">{{ line }}</div>
        </div>
      </NSpin>
    </div>

    <NAlert v-if="succeeded" type="success" class="result-alert">
      {{ t('flowStudio.redesignModal.success') }}
    </NAlert>
    <NAlert v-if="errorMsg" type="error" class="result-alert">{{ errorMsg }}</NAlert>

    <template #footer>
      <div class="modal-footer">
        <NButton :disabled="running" @click="handleClose">
          {{ succeeded ? t('common.ok') : t('common.cancel') }}
        </NButton>
        <NButton
          v-if="!succeeded"
          type="primary"
          :loading="running"
          :disabled="!canSubmit"
          @click="handleRedesign"
        >
          {{ t('flowStudio.redesignModal.redesign') }}
        </NButton>
      </div>
    </template>
  </NModal>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.output-panel {
  margin-top: 12px;
  background-color: rgba(0, 0, 0, 0.2);
  border: 1px solid $border-light;
  border-radius: $radius-md;
  padding: 10px 12px;
  max-height: 160px;
  overflow-y: auto;
  font-family: $font-code;
  font-size: 12px;
}

.output-lines {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.output-line {
  color: $text-secondary;
  white-space: pre-wrap;
  word-break: break-all;
}

.result-alert {
  margin-top: 12px;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
