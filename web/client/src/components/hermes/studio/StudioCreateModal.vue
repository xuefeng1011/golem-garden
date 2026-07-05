<script setup lang="ts">
/**
 * StudioCreateModal — Flow Studio 생성 위저드 (R2/R5/R8).
 * 1) 이름/경로/목표 입력 → POST /v1/studios
 * 2) 목표가 있으면 "AI 팀 생성"(forge studio design) 원클릭 옵션 제공 (ProjectInitModal SSE 패턴).
 *    목표를 건너뛰거나 design 완료 후 → 편집기로 이동.
 */
import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { NModal, NForm, NFormItem, NInput, NButton, NAlert, NSpin, useMessage } from 'naive-ui'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { createStudio, fetchStudioPresets } from '@/api/hermes/studios'
import type { StudioPreset } from '@/api/hermes/studios'
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

// ── 시작 방식 (① 빈 스튜디오 / ② 프리셋 / ③ AI 팀 설계) ─────────────────────
const startMode = ref<'blank' | 'preset' | 'ai'>('blank')
const presets = ref<StudioPreset[]>([])
const presetsLoading = ref(false)
const selectedPresetId = ref<string | null>(null)
// 프리셋 목록이 비어있으면(로딩 실패/무프리셋) ②를 숨기고 ①③만 노출한다.
const showPresetOption = computed(() => presetsLoading.value || presets.value.length > 0)

watch(showPresetOption, (available) => {
  if (!available && startMode.value === 'preset') startMode.value = 'blank'
})

onMounted(async () => {
  presetsLoading.value = true
  try {
    presets.value = await fetchStudioPresets()
  } catch {
    presets.value = []
  } finally {
    presetsLoading.value = false
  }
})

const running = ref(false)
const output = ref<string[]>([])
const result = ref<(ForgeCompletedEvent | ForgeFailedEvent) | null>(null)
const designError = ref<string | null>(null)

let streamHandle: { abort: () => void } | null = null

const succeeded = computed(
  () => result.value !== null && 'exit_code' in result.value && (result.value as ForgeCompletedEvent).exit_code === 0,
)
const failed = computed(() => result.value !== null && !succeeded.value)

const stageRunningText = computed(() =>
  startMode.value === 'preset' ? t('flowStudio.createModal.presetRunning') : t('flowStudio.createModal.designRunning'),
)
const stageSuccessText = computed(() =>
  startMode.value === 'preset' ? t('flowStudio.createModal.presetSuccess') : t('flowStudio.createModal.designSuccess'),
)
const stageFailedText = computed(() =>
  startMode.value === 'preset' ? t('flowStudio.createModal.presetFailed') : t('flowStudio.createModal.designFailed'),
)

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
  if (startMode.value === 'preset' && !selectedPresetId.value) {
    message.warning(t('flowStudio.errors.presetRequired'))
    return
  }
  if (startMode.value === 'ai') {
    if (!trimmedGoal) {
      message.warning(t('flowStudio.errors.goalRequired'))
      return
    }
    const err = validateForgeArg(trimmedGoal)
    if (err) {
      message.warning(t(`flowStudio.errors.${err}`))
      return
    }
  }

  creating.value = true
  try {
    const goalForCreate = startMode.value === 'ai' ? trimmedGoal : ''
    const studio = await createStudio(trimmedName, trimmedPath, goalForCreate)
    newStudioId.value = studio.id
    stage.value = 'design'
    message.success(t('flowStudio.createSuccess', { name: trimmedName }))
    emit('created')
    if (startMode.value === 'preset') runPresetApply()
  } catch (err) {
    message.error(mapCreateError(err))
  } finally {
    creating.value = false
  }
}

// design/preset apply 공용 SSE 실행 — args 만 다르다.
async function runStage(args: string[]) {
  if (!newStudioId.value) return
  running.value = true
  output.value = []
  result.value = null
  designError.value = null

  try {
    const { run_id } = await startForge(newStudioId.value, 'studio', args)
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

function runDesign() {
  if (!goal.value.trim()) return
  runStage(['design', goal.value.trim()])
}

function runPresetApply() {
  if (!selectedPresetId.value) return
  runStage(['preset', 'apply', selectedPresetId.value])
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
      <NFormItem :label="t('flowStudio.createModal.startModeLabel')">
        <div class="mode-group">
          <div
            class="mode-card"
            :class="{ active: startMode === 'blank' }"
            @click="startMode = 'blank'"
          >
            <strong>{{ t('flowStudio.createModal.modeBlank') }}</strong>
            <p>{{ t('flowStudio.createModal.modeBlankDesc') }}</p>
          </div>
          <div
            v-if="showPresetOption"
            class="mode-card"
            :class="{ active: startMode === 'preset' }"
            @click="startMode = 'preset'"
          >
            <strong>{{ t('flowStudio.createModal.modePreset') }}</strong>
            <p>{{ t('flowStudio.createModal.modePresetDesc') }}</p>
          </div>
          <div
            class="mode-card"
            :class="{ active: startMode === 'ai' }"
            @click="startMode = 'ai'"
          >
            <strong>{{ t('flowStudio.createModal.modeAi') }}</strong>
            <p>{{ t('flowStudio.createModal.modeAiDesc') }}</p>
          </div>
        </div>
      </NFormItem>

      <NFormItem v-if="startMode === 'preset'" :label="t('flowStudio.createModal.modePreset')">
        <NSpin v-if="presetsLoading" size="small" />
        <div v-else class="preset-grid">
          <div
            v-for="p in presets"
            :key="p.id"
            class="mode-card"
            :class="{ active: selectedPresetId === p.id }"
            @click="selectedPresetId = p.id"
          >
            <strong>{{ p.name }}</strong>
            <p>{{ p.description }}</p>
          </div>
        </div>
      </NFormItem>

      <NFormItem v-else-if="startMode === 'ai'" :label="t('flowStudio.createModal.goalLabel')" required>
        <NInput
          v-model:value="goal"
          type="textarea"
          :placeholder="t('flowStudio.createModal.goalPlaceholder')"
          :autosize="{ minRows: 2, maxRows: 5 }"
        />
      </NFormItem>
    </NForm>

    <!-- Stage 2: design/preset run -->
    <div v-else class="design-stage">
      <p v-if="startMode === 'blank'" class="design-hint">{{ t('flowStudio.createModal.skipDesignHint') }}</p>

      <template v-else>
        <div v-if="output.length > 0 || running" class="output-panel">
          <NSpin :show="running" size="small">
            <div class="output-lines">
              <div v-for="(line, i) in output" :key="i" class="output-line">{{ line }}</div>
              <div v-if="running && output.length === 0" class="output-placeholder">
                {{ stageRunningText }}
              </div>
            </div>
          </NSpin>
        </div>

        <NAlert v-if="succeeded" type="success" class="result-alert">
          {{ stageSuccessText }}
        </NAlert>
        <NAlert v-else-if="failed" type="error" class="result-alert">
          {{ stageFailedText }}
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
            v-if="startMode === 'ai' && !running && !succeeded"
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

.mode-group,
.preset-grid {
  display: flex;
  flex-direction: column;
  gap: 8px;
  width: 100%;
}

.mode-card {
  border: 1px solid $border-light;
  border-radius: $radius-md;
  padding: 8px 12px;
  cursor: pointer;
  transition: border-color $transition-fast, background $transition-fast;

  strong {
    display: block;
    font-size: 13px;
    color: $text-primary;
  }

  p {
    margin: 2px 0 0;
    font-size: 12px;
    color: $text-muted;
  }

  &:hover {
    border-color: $accent-primary;
  }

  &.active {
    border-color: $accent-primary;
    background: rgba(var(--accent-primary-rgb), 0.08);
  }
}

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
