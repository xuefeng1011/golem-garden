<script setup lang="ts">
import { ref, computed } from 'vue'
import { NModal, NButton, NAlert, NSpin } from 'naive-ui'
import { startForge, streamForgeEvents } from '@/api/hermes/forge'
import type { ForgeCompletedEvent, ForgeFailedEvent } from '@/api/hermes/forge'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  projectId: string
  projectName: string
  open: boolean
  existingSoulsCount?: number
}>()

const emit = defineEmits<{
  close: []
  initialized: []
}>()

const { t } = useI18n()

const PACKS = [
  { id: 'fullstack', name: t('init.packs.fullstack.name'), description: t('init.packs.fullstack.description') },
  { id: 'gamedev',   name: t('init.packs.gamedev.name'),   description: t('init.packs.gamedev.description') },
  { id: 'trading',   name: t('init.packs.trading.name'),   description: t('init.packs.trading.description') },
]

const selectedPack = ref<string>('fullstack')
const running = ref(false)
const output = ref<string[]>([])
const result = ref<(ForgeCompletedEvent | ForgeFailedEvent) | null>(null)
const error = ref<string | null>(null)
const showConfirmOverwrite = ref(false)

let streamHandle: { abort: () => void } | null = null

const succeeded = computed(
  () => result.value !== null && 'exit_code' in result.value && (result.value as ForgeCompletedEvent).exit_code === 0,
)

const failed = computed(
  () => result.value !== null && !succeeded.value,
)

const selectedPackInfo = computed(() => PACKS.find((p) => p.id === selectedPack.value))

function handleInstallClick() {
  if (running.value) return
  if ((props.existingSoulsCount ?? 0) > 0 && !showConfirmOverwrite.value) {
    showConfirmOverwrite.value = true
    return
  }
  runInstall()
}

function handleRetry() {
  result.value = null
  error.value = null
  output.value = []
  showConfirmOverwrite.value = false
  running.value = false
}

function handleAbort() {
  streamHandle?.abort()
  streamHandle = null
  running.value = false
  output.value.push('[중단됨]')
}

async function runInstall() {
  if (running.value) return
  running.value = true
  showConfirmOverwrite.value = false
  output.value = []
  result.value = null
  error.value = null

  try {
    const { run_id } = await startForge(props.projectId, 'pack', ['install', selectedPack.value])
    streamHandle = streamForgeEvents(
      run_id,
      (evt) => {
        if (evt.line !== undefined) {
          output.value.push(evt.line)
        }
      },
      (done) => {
        result.value = done
        running.value = false
        streamHandle = null
        if ('exit_code' in done && done.exit_code === 0) {
          emit('initialized')
        }
      },
      (err) => {
        error.value = err.message
        running.value = false
        streamHandle = null
      },
    )
  } catch (err) {
    error.value = err instanceof Error ? err.message : '알 수 없는 오류'
    running.value = false
  }
}

function handleClose() {
  if (running.value) return
  emit('close')
}
</script>

<template>
  <NModal
    :show="open"
    preset="card"
    :title="t('init.title', { name: projectName })"
    :style="{ width: 'min(640px, calc(100vw - 32px))' }"
    :mask-closable="!running"
    :close-on-esc="!running"
    @close="handleClose"
    @mask-click="handleClose"
  >
    <!-- Pack selector (disabled while running) -->
    <div class="pack-selector" :class="{ disabled: running }">
      <p class="selector-label">{{ t('init.choosePack') }}</p>
      <div class="pack-grid">
        <div
          v-for="pack in PACKS"
          :key="pack.id"
          class="pack-card"
          :class="{ selected: selectedPack === pack.id, disabled: running }"
          @click="!running && (selectedPack = pack.id)"
        >
          <div class="pack-name">{{ pack.name }}</div>
          <div class="pack-desc">{{ pack.description }}</div>
        </div>
      </div>
    </div>

    <!-- Overwrite confirmation -->
    <NAlert v-if="showConfirmOverwrite" type="warning" class="overwrite-alert">
      {{ t('init.overwriteWarning', { count: existingSoulsCount }) }}
      <div class="overwrite-actions">
        <NButton size="small" @click="showConfirmOverwrite = false">{{ t('common.cancel') }}</NButton>
        <NButton size="small" type="warning" @click="runInstall">{{ t('init.overwriteConfirm') }}</NButton>
      </div>
    </NAlert>

    <!-- Output panel (visible once running or done) -->
    <div v-if="output.length > 0 || running || result !== null" class="output-panel">
      <NSpin :show="running" size="small">
        <div class="output-lines">
          <div
            v-for="(line, i) in output"
            :key="i"
            class="output-line"
          >{{ line }}</div>
          <div v-if="running && output.length === 0" class="output-placeholder">
            {{ t('init.installing') }}
          </div>
        </div>
      </NSpin>
    </div>

    <!-- Result banners -->
    <NAlert v-if="succeeded" type="success" class="result-alert">
      {{ t('init.success') }}
    </NAlert>
    <NAlert v-else-if="failed" type="error" class="result-alert">
      {{ t('init.error') }}
    </NAlert>
    <NAlert v-if="error" type="error" class="result-alert">{{ error }}</NAlert>

    <template #footer>
      <div class="modal-footer">
        <NButton :disabled="running" @click="handleClose">{{ t('common.cancel') }}</NButton>

        <NButton
          v-if="failed || error"
          type="default"
          @click="handleRetry"
        >
          {{ t('common.retry') }}
        </NButton>

        <NButton
          v-if="running"
          type="default"
          @click="handleAbort"
        >
          {{ t('init.abort') }}
        </NButton>

        <NButton
          v-if="!running && !succeeded"
          type="primary"
          :disabled="!selectedPack"
          @click="handleInstallClick"
        >
          {{ t('init.install', { pack: selectedPackInfo?.name ?? '' }) }}
        </NButton>
      </div>
    </template>
  </NModal>
</template>

<style scoped lang="scss">
@use '@/styles/variables' as *;

.selector-label {
  font-size: 13px;
  color: $text-muted;
  margin-bottom: 10px;
}

.pack-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  margin-bottom: 16px;

  @media (max-width: 480px) {
    grid-template-columns: 1fr;
  }
}

.pack-card {
  border: 1px solid $border-color;
  border-radius: $radius-md;
  padding: 12px;
  cursor: pointer;
  transition: border-color $transition-fast, background-color $transition-fast;

  &:hover:not(.disabled) {
    border-color: rgba(var(--accent-primary-rgb), 0.5);
  }

  &.selected {
    border-color: rgba(var(--accent-primary-rgb), 1);
    background-color: rgba(var(--accent-primary-rgb), 0.08);
  }

  &.disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
}

.pack-name {
  font-size: 13px;
  font-weight: 600;
  color: $text-primary;
  margin-bottom: 4px;
}

.pack-desc {
  font-size: 11px;
  color: $text-muted;
  line-height: 1.4;
}

.pack-selector.disabled {
  pointer-events: none;
  opacity: 0.7;
}

.overwrite-alert {
  margin-bottom: 12px;
}

.overwrite-actions {
  display: flex;
  gap: 8px;
  margin-top: 8px;
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
