<script setup lang="ts">
/**
 * StudioCreateModal — Flow Studio 생성 위저드 (R2/R5/R8).
 * 1) 이름/경로/목표 입력 → POST /v1/studios
 * 2) 목표가 있으면 "AI 팀 생성"(forge studio design) 원클릭 옵션 제공 (ProjectInitModal SSE 패턴).
 *    목표를 건너뛰거나 design 완료 후 → 편집기로 이동.
 */
import { ref, computed, onUnmounted } from 'vue'
import { NModal, NForm, NFormItem, NInput, NButton, NAlert, NSpin, useMessage } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { createStudio } from '@/api/hermes/studios'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import type { ForgeCompletedEvent, ForgeFailedEvent } from '@/api/hermes/forge'
import { validateForgeArg } from '@/utils/forge-args'

const emit = defineEmits<{
  close: []
  created: []
}>()

const { t } = useI18n()
const message = useMessage()
const router = useRouter()

const showModal = ref(true)
const stage = ref<'form' | 'design'>('form')
const creating = ref(false)

const name = ref('')
const path = ref('')
const goal = ref('')
const newStudioId = ref<string | null>(null)

const running = ref(false)
const output = ref<string[]>([])
const result = ref<(ForgeCompletedEvent | ForgeFailedEvent) | null>(null)
const designError = ref<string | null>(null)

let streamHandle: { abort: () => void } | null = null

const succeeded = computed(
  () => result.value !== null && 'exit_code' in result.value && (result.value as ForgeCompletedEvent).exit_code === 0,
)
const failed = computed(() => result.value !== null && !succeeded.value)

function mapCreateError(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err)
  if (msg.includes('409')) return t('flowStudio.errors.duplicate')
  if (msg.includes('400')) return t('flowStudio.errors.invalidPath')
  if (msg.includes('500')) return t('flowStudio.errors.initFailed')
  return `${t('flowStudio.errors.createFailed')}: ${msg}`
}

async function handleCreate() {
  if (creating.value) return
  const trimmedName = name.value.trim()
  const trimmedPath = path.value.trim()
  const trimmedGoal = goal.value.trim()

  if (!trimmedName) {
    message.warning(t('flowStudio.errors.nameRequired'))
    return
  }
  if (!trimmedPath) {
    message.warning(t('flowStudio.errors.pathRequired'))
    return
  }
  if (trimmedGoal) {
    const err = validateForgeArg(trimmedGoal)
    if (err) {
      message.warning(t(`flowStudio.errors.${err}`))
      return
    }
  }

  creating.value = true
  try {
    const studio = await createStudio(trimmedName, trimmedPath, trimmedGoal)
    newStudioId.value = studio.id
    stage.value = 'design'
    message.success(t('flowStudio.createSuccess', { name: trimmedName }))
    emit('created')
  } catch (err) {
    message.error(mapCreateError(err))
  } finally {
    creating.value = false
  }
}

async function runDesign() {
  if (!newStudioId.value || !goal.value.trim()) return
  running.value = true
  output.value = []
  result.value = null
  designError.value = null

  try {
    const { run_id } = await startForge(newStudioId.value, 'studio', ['design', goal.value.trim()])
    streamHandle = streamForgeEvents(
      run_id,
      (evt) => { if (evt.line !== undefined) output.value.push(evt.line) },
      (done) => {
        result.value = done
        running.value = false
        streamHandle = null
      },
      (err) => {
        designError.value = err.message
        running.value = false
        streamHandle = null
      },
    )
  } catch (err) {
    designError.value = err instanceof Error ? err.message : String(err)
    running.value = false
  }
}

function openEditor() {
  const id = newStudioId.value
  if (!id) return
  handleClose()
  router.push({ name: 'hermes.flowStudio.editor', params: { projectId: id } })
}

function handleClose() {
  if (running.value) return
  streamHandle?.abort()
  streamHandle = null
  showModal.value = false
}

onUnmounted(() => {
  streamHandle?.abort()
  streamHandle = null
})
</script>

<template>
  <NModal
    :show="showModal"
    preset="card"
    :title="t('flowStudio.createModal.title')"
    :style="{ width: 'min(520px, calc(100vw - 32px))' }"
    :mask-closable="!creating && !running"
    :close-on-esc="!creating && !running"
    @close="handleClose"
    @mask-click="handleClose"
    @after-leave="emit('close')"
  >
    <!-- Stage 1: form -->
    <NForm v-if="stage === 'form'" label-placement="top">
      <NFormItem :label="t('flowStudio.createModal.nameLabel')" required>
        <NInput
          v-model:value="name"
          :placeholder="t('flowStudio.createModal.namePlaceholder')"
          @keyup.enter="handleCreate"
        />
      </NFormItem>
      <NFormItem :label="t('flowStudio.createModal.pathLabel')" required>
        <NInput
          v-model:value="path"
          :placeholder="t('flowStudio.createModal.pathPlaceholder')"
          @keyup.enter="handleCreate"
        />
      </NFormItem>
      <NFormItem :label="t('flowStudio.createModal.goalLabel')">
        <NInput
          v-model:value="goal"
          type="textarea"
          :placeholder="t('flowStudio.createModal.goalPlaceholder')"
          :autosize="{ minRows: 2, maxRows: 5 }"
        />
      </NFormItem>
    </NForm>

    <!-- Stage 2: design run -->
    <div v-else class="design-stage">
      <p v-if="!goal.trim()" class="design-hint">{{ t('flowStudio.createModal.skipDesignHint') }}</p>

      <template v-else>
        <div v-if="output.length > 0 || running" class="output-panel">
          <NSpin :show="running" size="small">
            <div class="output-lines">
              <div v-for="(line, i) in output" :key="i" class="output-line">{{ line }}</div>
              <div v-if="running && output.length === 0" class="output-placeholder">
                {{ t('flowStudio.createModal.designRunning') }}
              </div>
            </div>
          </NSpin>
        </div>

        <NAlert v-if="succeeded" type="success" class="result-alert">
          {{ t('flowStudio.createModal.designSuccess') }}
        </NAlert>
        <NAlert v-else-if="failed" type="error" class="result-alert">
          {{ t('flowStudio.createModal.designFailed') }}
        </NAlert>
        <NAlert v-if="designError" type="error" class="result-alert">{{ designError }}</NAlert>
      </template>
    </div>

    <template #footer>
      <div class="modal-footer">
        <!-- Stage 1 footer -->
        <template v-if="stage === 'form'">
          <NButton @click="handleClose">{{ t('common.cancel') }}</NButton>
          <NButton type="primary" :loading="creating" :disabled="creating" @click="handleCreate">
            {{ t('common.create') }}
          </NButton>
        </template>

        <!-- Stage 2 footer -->
        <template v-else>
          <NButton :disabled="running" @click="openEditor">
            {{ t('flowStudio.createModal.skipDesign') }}
          </NButton>
          <NButton
            v-if="goal.trim() && !running && !succeeded"
            type="primary"
            @click="runDesign"
          >
            {{ t('flowStudio.createModal.designRun') }}
          </NButton>
          <NButton v-if="succeeded" type="primary" @click="openEditor">
            {{ t('flowStudio.createModal.openEditor') }}
          </NButton>
        </template>
      </div>
    </template>
  </NModal>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.design-hint {
  font-size: 13px;
  color: $text-muted;
}

.output-panel {
  background-color: rgba(0, 0, 0, 0.2);
  border: 1px solid $border-light;
  border-radius: $radius-md;
  padding: 10px 12px;
  max-height: 240px;
  overflow-y: auto;
  font-family: $font-code;
  font-size: 12px;
  margin-bottom: 12px;
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

.output-placeholder {
  color: $text-muted;
  font-style: italic;
}

.result-alert {
  margin-bottom: 8px;
}

.modal-footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  flex-wrap: wrap;
}
</style>
