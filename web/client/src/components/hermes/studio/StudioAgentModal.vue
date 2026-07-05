<script setup lang="ts">
/**
 * StudioAgentModal — Flow Studio 컨텍스트에서 에이전트(SOUL)를 자유 생성 (R3/R9).
 * forge studio agent-add <dir> <name> <model> <role> [rules] 를 SSE로 스트리밍 실행하고,
 * 완료 시 부모가 souls 목록을 재조회하도록 'created' 를 emit 한다.
 */
import { ref, computed } from 'vue'
import { NModal, NForm, NFormItem, NInput, NSelect, NButton, NAlert, NSpin } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import { validateForgeArg } from '@/utils/forge-args'

const props = defineProps<{
  show: boolean
  projectId: string
}>()

const emit = defineEmits<{
  'update:show': [boolean]
  created: []
}>()

const { t } = useI18n()

const NAME_RE = /^[a-z0-9-]+$/
// studio.sh agent-add 의 model 가드와 동일 패턴 (직접 입력 값 사전 검증)
const MODEL_RE = /^[a-zA-Z0-9._-]+$/

const name = ref('')
const model = ref<string>('sonnet')
const role = ref('')
const rules = ref('')
const rank = ref<'novice' | 'junior' | 'senior' | 'expert' | 'master'>('novice')
const effort = ref<'' | 'low' | 'medium' | 'high'>('')

const running = ref(false)
const output = ref<string[]>([])
const succeeded = ref(false)
const errorMsg = ref<string | null>(null)

let streamHandle: { abort: () => void } | null = null

// 별칭(haiku/sonnet/opus)은 claude CLI 가 항상 최신 모델로 해석한다.
// 전체 ID 는 특정 모델 고정용 — 목록에 없는 모델은 직접 입력(tag) 가능.
const modelOptions = [
  { label: `haiku (${t('flowStudio.agentModal.aliasLatest')})`, value: 'haiku' },
  { label: `sonnet (${t('flowStudio.agentModal.aliasLatest')})`, value: 'sonnet' },
  { label: `opus (${t('flowStudio.agentModal.aliasLatest')})`, value: 'opus' },
  { label: 'claude-fable-5', value: 'claude-fable-5' },
  { label: 'claude-opus-4-8', value: 'claude-opus-4-8' },
  { label: 'claude-opus-4-7', value: 'claude-opus-4-7' },
  { label: 'claude-sonnet-5', value: 'claude-sonnet-5' },
  { label: 'claude-sonnet-4-6', value: 'claude-sonnet-4-6' },
  { label: 'claude-haiku-4-5', value: 'claude-haiku-4-5' },
]

const rankOptions = [
  { label: 'novice', value: 'novice' },
  { label: 'junior', value: 'junior' },
  { label: 'senior', value: 'senior' },
  { label: 'expert', value: 'expert' },
  { label: 'master', value: 'master' },
]

const effortOptions = [
  { label: t('flowStudio.agentModal.effortNone'), value: '' },
  { label: 'low', value: 'low' },
  { label: 'medium', value: 'medium' },
  { label: 'high', value: 'high' },
]

const canSubmit = computed(() => !running.value && !succeeded.value)

function validate(): boolean {
  const trimmedName = name.value.trim()
  if (!trimmedName || !NAME_RE.test(trimmedName)) {
    errorMsg.value = t('flowStudio.errors.nameInvalid')
    return false
  }
  if (!MODEL_RE.test(model.value.trim())) {
    errorMsg.value = t('flowStudio.errors.modelInvalid')
    return false
  }
  for (const v of [role.value, rules.value]) {
    const err = validateForgeArg(v)
    if (err) {
      errorMsg.value = t(`flowStudio.errors.${err}`)
      return false
    }
  }
  errorMsg.value = null
  return true
}

async function handleCreate() {
  if (!validate()) return

  running.value = true
  output.value = []
  succeeded.value = false

  try {
    const { run_id } = await startForge(props.projectId, 'studio', [
      'agent-add',
      name.value.trim(),
      model.value.trim(),
      role.value.trim(),
      rules.value.trim(),
      rank.value,
      effort.value,
    ])

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
          emit('created')
        } else {
          errorMsg.value = t('flowStudio.errors.createFailed')
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
  name.value = ''
  model.value = 'sonnet'
  role.value = ''
  rules.value = ''
  rank.value = 'novice'
  effort.value = ''
  output.value = []
  succeeded.value = false
  errorMsg.value = null
  emit('update:show', false)
}
</script>

<template>
  <NModal
    :show="show"
    preset="card"
    :title="t('flowStudio.agentModal.title')"
    :style="{ width: 'min(480px, calc(100vw - 32px))' }"
    :mask-closable="!running"
    :close-on-esc="!running"
    @update:show="(v: boolean) => { if (!v) handleClose() }"
  >
    <NForm label-placement="top" :disabled="!canSubmit">
      <NFormItem :label="t('flowStudio.agentModal.nameLabel')" required>
        <NInput v-model:value="name" :placeholder="t('flowStudio.agentModal.namePlaceholder')" />
      </NFormItem>
      <NFormItem :label="t('flowStudio.agentModal.modelLabel')" required>
        <!-- filterable+tag — 목록에 없는 새 모델 ID 도 직접 입력해 사용 가능 -->
        <NSelect v-model:value="model" :options="modelOptions" filterable tag />
      </NFormItem>
      <NFormItem :label="t('flowStudio.agentModal.roleLabel')" required>
        <NInput v-model:value="role" :placeholder="t('flowStudio.agentModal.rolePlaceholder')" />
      </NFormItem>
      <NFormItem :label="t('flowStudio.agentModal.rulesLabel')">
        <NInput
          v-model:value="rules"
          type="textarea"
          :placeholder="t('flowStudio.agentModal.rulesPlaceholder')"
          :autosize="{ minRows: 2, maxRows: 5 }"
        />
      </NFormItem>
      <NFormItem :label="t('flowStudio.agentModal.rankLabel')" required>
        <NSelect v-model:value="rank" :options="rankOptions" />
      </NFormItem>
      <NFormItem :label="t('flowStudio.agentModal.effortLabel')">
        <NSelect v-model:value="effort" :options="effortOptions" />
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
      {{ t('flowStudio.agentModal.success') }}
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
          @click="handleCreate"
        >
          {{ t('flowStudio.agentModal.create') }}
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
